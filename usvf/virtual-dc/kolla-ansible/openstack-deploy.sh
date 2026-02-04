#!/bin/bash
# =============================================================================
# OpenStack Deployment Script with Kolla-Ansible and External Ceph
# =============================================================================
#
# This script deploys OpenStack using Kolla-Ansible with an existing Ceph cluster
# as the storage backend.
#
# Prerequisites:
#   - Ceph cluster already deployed (hypervisor-1,2,3 = MON/MGR, hypervisor-4,5 = OSD)
#   - SSH access from deployment host to all hypervisors
#   - Pools already created: images, volumes, vms, backups
#
# Architecture:
#   - Control Plane: hypervisor-1, hypervisor-2, hypervisor-3 (192.168.10.11-13)
#   - Compute/Storage: hypervisor-4, hypervisor-5 (192.168.10.14-15)
#   - VIP: 10.100.0.254 (Anycast on all controllers)
#
# Usage:
#   ./openstack-deploy.sh
#
# =============================================================================

set -e  # Exit on error

# =============================================================================
# Configuration Variables
# =============================================================================

# Subnet base (REQUIRED - use --subnet=192.168.10 or --subnet=192.168.11)
SUBNET_BASE=""

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --subnet=*)
            SUBNET_BASE="${arg#*=}"
            SUBNET_BASE="${SUBNET_BASE%.0/24}"
            SUBNET_BASE="${SUBNET_BASE%.0}"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 --subnet=<subnet_base> [phase]"
            echo "  Example: $0 --subnet=192.168.10          # full deploy on dc1"
            echo "  Example: $0 --subnet=192.168.11          # full deploy on dc2"
            echo "  Example: $0 --subnet=192.168.11 bootstrap # bootstrap only on dc2"
            exit 0
            ;;
    esac
done

# Subnet validation currently disabled - scripts default to dc1 (192.168.10)
# To enforce --subnet parameter requirement, uncomment the validation below:
# if [ -z "$SUBNET_BASE" ]; then
#     echo "ERROR: --subnet is required"
#     echo "Usage: $0 --subnet=192.168.10   # for dc1"
#     echo "       $0 --subnet=192.168.11   # for dc2"
#     exit 1
# fi

# Deployment host settings
KOLLA_VENV="$HOME/kolla-venv"
# Each DC gets its own kolla config directory to avoid conflicts
# dc1 (192.168.10) -> /etc/kolla-dc1
# dc2 (192.168.11) -> /etc/kolla-dc2
# SUBNET_OCTET="${SUBNET_BASE##*.}"  # Extract last octet (10, 11, etc.)
KOLLA_CONFIG="/etc/kolla"

# Ceph admin node (where to run ceph commands)
CEPH_ADMIN_NODE="192.168.10.11"
CEPH_ADMIN_IP="192.168.10.11"

# Controller nodes (derived from subnet)
CONTROLLERS=("192.168.10.11" "192.168.10.12" "192.168.10.13")
CONTROLLER_NAMES=("hypervisor-1" "hypervisor-2" "hypervisor-3")

# Compute nodes (derived from subnet)
COMPUTES=("192.168.10.11" "192.168.10.12" "192.168.10.13")
COMPUTE_NAMES=("hypervisor-1" "hypervisor-2" "hypervisor-3")

# All nodes
ALL_NODES=("${CONTROLLERS[@]}")

# VIP for OpenStack API (each DC gets a unique VIP)
# dc1 (192.168.10) -> 10.100.0.254
# dc2 (192.168.11) -> 10.100.0.253
# dc3 (192.168.12) -> 10.100.0.252, etc.
VIP="10.100.0.254"

# Kolla-Ansible version
KOLLA_VERSION="19.2.0"
OPENSTACK_RELEASE="2024.2"

# SSH user for nodes
SSH_USER="ubuntu"

# SSH key configuration
SSH_KEY="$HOME/usvf/usvf/virtual-dc/config/vdc-dc1/ssh-keys/id_rsa"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${SSH_KEY}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo "============================================================================="
    echo -e "${GREEN}$1${NC}"
    echo "============================================================================="
    echo ""
}

run_on_node() {
    local node=$1
    shift
    ssh ${SSH_OPTS} ${SSH_USER}@${node} "$@"
}

run_on_node_sudo() {
    local node=$1
    shift
    ssh ${SSH_OPTS} ${SSH_USER}@${node} "sudo $@"
}

wait_for_apt_lock() {
    local host=$1
    local max_wait=300
    local interval=5
    local elapsed=0

    while [ $elapsed -lt $max_wait ]; do
        if run_on_node "$host" "sudo bash -c '
            ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 &&
            ! fuser /var/lib/dpkg/lock >/dev/null 2>&1 &&
            ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1 &&
            ! fuser /var/cache/apt/archives/lock >/dev/null 2>&1
        '"; then
            return 0
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    return 1
}

# ---------------------------------------------------------------------------
# clean_ssh_known_hosts: Remove stale SSH host keys for all hypervisors
# This is needed when VMs are destroyed and recreated with new SSH keys
# ---------------------------------------------------------------------------
clean_ssh_known_hosts() {
    log_info "Cleaning SSH known_hosts for all hypervisors..."

    # Remove old keys for all nodes
    for ip in "${CONTROLLERS[@]}" "${COMPUTES[@]}"; do
        ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$ip" 2>/dev/null || true
    done

    # Accept new keys with StrictHostKeyChecking=accept-new
    for ip in "${CONTROLLERS[@]}" "${COMPUTES[@]}"; do
        ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -i ${SSH_KEY} ubuntu@"$ip" 'echo OK' 2>/dev/null || true
    done

    log_success "SSH known_hosts cleaned and new keys accepted"
}

# ---------------------------------------------------------------------------
# ensure_docker_running: Make Docker work on a node regardless of current state
# Handles: docker not installed, docker failed, docker.socket masked, etc.
# ---------------------------------------------------------------------------
ensure_docker_running() {
    local node=$1
    run_on_node "$node" "sudo bash -c '
        if ! command -v docker &>/dev/null; then
            echo \"Docker not installed on \$(hostname), skipping\"
            exit 0
        fi
        # Reset any failed state
        systemctl reset-failed docker 2>/dev/null || true
        # Unmask socket (kolla-ansible sometimes masks it)
        systemctl unmask docker.socket 2>/dev/null || true
        # Apply systemd drop-in so Docker can always restart cleanly
        mkdir -p /etc/systemd/system/docker.service.d
        cat > /etc/systemd/system/docker.service.d/kolla-ceph-compat.conf << DROPEOF
[Unit]
After=docker.socket
[Service]
ExecStartPre=/bin/bash -c \"systemctl unmask docker.socket 2>/dev/null; systemctl start docker.socket 2>/dev/null; true\"
DROPEOF
        systemctl daemon-reload
        # Start socket then service
        systemctl start docker.socket 2>/dev/null || true
        systemctl start docker 2>/dev/null || true
        if systemctl is-active --quiet docker; then
            echo \"Docker OK on \$(hostname)\"
        else
            echo \"Docker FAILED on \$(hostname) - attempting full restart\" >&2
            rm -f /var/run/docker.pid 2>/dev/null || true
            systemctl restart docker
        fi
    '" 2>/dev/null
}

# ---------------------------------------------------------------------------
# ensure_ceph_running: Start all Ceph daemons on a node
# Handles: daemons stopped from previous bootstrap, target not started, etc.
# ---------------------------------------------------------------------------
ensure_ceph_running() {
    local node=$1
    run_on_node "$node" "sudo bash -c '
        # Unmask in case it was masked
        systemctl unmask ceph.target 2>/dev/null || true
        # Start the ceph target
        systemctl start ceph.target 2>/dev/null || true
        # Start all ceph-related targets (ceph-<fsid>.target)
        for tgt in \$(systemctl list-unit-files --type=target --all --no-legend 2>/dev/null | grep \"ceph-\" | awk \"{print \\\$1}\"); do
            systemctl unmask \"\$tgt\" 2>/dev/null || true
            systemctl start \"\$tgt\" 2>/dev/null || true
        done
    '" 2>/dev/null
}

# ---------------------------------------------------------------------------
# ensure_all_healthy: Bring Docker + Ceph to a healthy state on all nodes
# Call this before any phase that depends on working Docker or Ceph.
# ---------------------------------------------------------------------------
ensure_all_healthy() {
    log_info "Ensuring Docker and Ceph are running on all nodes..."
    for node in "${ALL_NODES[@]}"; do
        ensure_docker_running "$node"
        ensure_ceph_running "$node"
    done
    # Give Ceph daemons a moment to form quorum
    sleep 5
}

# ---------------------------------------------------------------------------
# stop_all_ceph: Aggressively stop every Ceph daemon + container on a node
# Used before bootstrap so Docker can restart without Ceph blocking it.
# ---------------------------------------------------------------------------
stop_all_ceph() {
    local node=$1
    run_on_node "$node" "sudo bash -c '
        # Stop ceph targets
        for tgt in \$(systemctl list-units --type=target --all --no-legend 2>/dev/null | grep \"ceph\" | awk \"{print \\\$1}\"); do
            systemctl stop \"\$tgt\" 2>/dev/null || true
        done
        systemctl stop ceph.target 2>/dev/null || true
        # Stop every individual ceph service unit
        for svc in \$(systemctl list-units --type=service --all --no-legend 2>/dev/null | grep \"ceph\" | awk \"{print \\\$1}\"); do
            systemctl stop \"\$svc\" 2>/dev/null || true
        done
        sleep 2
        # Kill any remaining ceph containers
        if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
            docker ps -q --filter name=ceph | xargs -r docker stop --time=5 2>/dev/null || true
            docker ps -q --filter name=ceph | xargs -r docker kill 2>/dev/null || true
        fi
    '" 2>/dev/null
}

# ---------------------------------------------------------------------------
# nuke_ceph_containers: Remove ALL ceph containers + mask ceph.target
# This is needed before kolla-ansible bootstrap because:
#   1. Kolla masks docker.socket, installs docker, then starts docker
#   2. When docker starts, it tries to restore containers with restart=always
#   3. Ceph containers (managed by cephadm) have restart=always
#   4. If ceph containers fail to start (resources unavailable), docker crashes
# Solution: Remove ceph containers entirely before bootstrap. cephadm will
# recreate them when we unmask and start ceph.target afterward.
# ---------------------------------------------------------------------------
nuke_ceph_containers() {
    local node=$1
    log_info "Removing ceph containers and masking ceph.target on $node..."
    run_on_node "$node" "sudo bash -c '
        # 1. Mask ceph.target so systemd wont restart ceph during docker changes
        systemctl mask ceph.target 2>/dev/null || true

        # 2. Stop all ceph systemd units (targets + template services)
        for unit in \$(systemctl list-units --type=target --all --no-legend 2>/dev/null | grep \"ceph\" | awk \"{print \\\$1}\"); do
            systemctl stop \"\$unit\" 2>/dev/null || true
            systemctl mask \"\$unit\" 2>/dev/null || true
        done
        for svc in \$(systemctl list-units --type=service --all --no-legend 2>/dev/null | grep \"ceph\" | awk \"{print \\\$1}\"); do
            systemctl stop \"\$svc\" 2>/dev/null || true
        done
        systemctl stop ceph.target 2>/dev/null || true
        sleep 2

        # 3. If docker is running, remove ALL ceph containers
        #    (cephadm will recreate them - state is on disk, not in containers)
        if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
            # Change restart policy first so docker wont try to restart them
            docker ps -aq --filter name=ceph 2>/dev/null | xargs -r docker update --restart=no 2>/dev/null || true
            # Force remove all ceph containers
            docker ps -aq --filter name=ceph 2>/dev/null | xargs -r docker rm -f 2>/dev/null || true
        fi

        # 4. Stop docker completely and clean up stale state
        systemctl stop docker 2>/dev/null || true
        systemctl stop docker.socket 2>/dev/null || true
        rm -f /var/run/docker.pid 2>/dev/null || true

        # 5. Unmask docker (in case left from previous failed bootstrap)
        systemctl unmask docker.service 2>/dev/null || true
        systemctl unmask docker.socket 2>/dev/null || true
        systemctl reset-failed docker 2>/dev/null || true
        systemctl daemon-reload

        # 6. Restore Docker systemd override (from ceph-cluster-setup)
        mkdir -p /etc/systemd/system/docker.service.d
        cat > /etc/systemd/system/docker.service.d/override.conf << OVERRIDE
[Service]
Type=notify
NotifyAccess=main
OVERRIDE
        systemctl daemon-reload

        # 7. Start docker clean (no ceph containers to restore)
        systemctl start docker.socket 2>/dev/null || true
        systemctl start docker

        if systemctl is-active --quiet docker; then
            echo \"Docker clean-started OK on \$(hostname)\"
        else
            echo \"Docker FAILED to start on \$(hostname)\" >&2
            journalctl -xeu docker.service --no-pager -n 20 >&2
            exit 1
        fi
    '"
}

# ---------------------------------------------------------------------------
# restore_ceph_after_bootstrap: Unmask ceph.target, let cephadm recreate containers
# ---------------------------------------------------------------------------
restore_ceph_after_bootstrap() {
    local node=$1
    log_info "Restoring Ceph on $node..."
    run_on_node "$node" "sudo bash -c '
        # Unmask all ceph targets
        systemctl unmask ceph.target 2>/dev/null || true
        for tgt in \$(systemctl list-unit-files --type=target --all --no-legend 2>/dev/null | grep \"ceph-\" | awk \"{print \\\$1}\"); do
            systemctl unmask \"\$tgt\" 2>/dev/null || true
            systemctl enable \"\$tgt\" 2>/dev/null || true
        done

        # Re-enable the ceph template service (ceph-<fsid>@.service)
        for svc in \$(systemctl list-unit-files --type=service --all --no-legend 2>/dev/null | grep \"ceph-\" | awk \"{print \\\$1}\"); do
            systemctl enable \"\$svc\" 2>/dev/null || true
        done

        # Start ceph targets - this triggers cephadm to recreate containers
        systemctl start ceph.target 2>/dev/null || true
        for tgt in \$(systemctl list-unit-files --type=target --all --no-legend 2>/dev/null | grep \"ceph-\" | awk \"{print \\\$1}\"); do
            systemctl start \"\$tgt\" 2>/dev/null || true
        done

        # Also directly ask cephadm to adopt/redeploy if available
        if command -v cephadm &>/dev/null; then
            FSID=\$(ls /var/lib/ceph/ 2>/dev/null | head -1)
            if [ -n \"\$FSID\" ]; then
                echo \"Triggering cephadm to redeploy daemons (fsid=\$FSID)...\"
                cephadm ls 2>/dev/null | python3 -c \"
import sys,json
for d in json.load(sys.stdin):
    print(d.get(\\\"name\\\",\\\"\\\"))
\" 2>/dev/null | while read name; do
                    [ -z \"\$name\" ] && continue
                    cephadm adopt --style legacy --name \"\$name\" 2>/dev/null || \
                    cephadm deploy --fsid \"\$FSID\" --name \"\$name\" 2>/dev/null || true
                done
            fi
        fi
    '" 2>/dev/null
}

# ---------------------------------------------------------------------------
# destroy_kolla: Remove ALL Kolla containers from all nodes (fresh start)
# This is the nuclear option - removes all OpenStack containers + volumes
# ---------------------------------------------------------------------------
destroy_kolla() {
    log_section "Destroying stale Kolla deployment on all nodes"

    source "$KOLLA_VENV/bin/activate" 2>/dev/null || true

    # Try kolla-ansible destroy first (graceful)
    if [ -f "$KOLLA_CONFIG/multinode" ]; then
        log_info "Running kolla-ansible destroy (graceful cleanup)..."
        cd "$KOLLA_CONFIG"
        kolla-ansible destroy -i multinode --yes-i-really-really-mean-it 2>/dev/null || true
    fi

    # Then manually clean up any leftovers on every node
    log_info "Manually cleaning up containers on all nodes..."
    for node in "${ALL_NODES[@]}"; do
        log_info "Cleaning $node..."
        run_on_node "$node" "sudo bash -c '
            # Stop and remove all kolla containers by label
            docker ps -a --filter \"label=kolla_version\" -q 2>/dev/null | xargs -r docker rm -f 2>/dev/null || true
            # Catch containers by name pattern (including stopped ones)
            docker ps -a --format \"{{.Names}}\" 2>/dev/null | grep -E \"^(kolla_|nova_|neutron_|cinder_|glance_|keystone_|horizon_|heat_|mariadb|rabbitmq|memcached|haproxy|proxysql|fluentd|cron|kolla|openvswitch|ovn)\" | xargs -r docker rm -f 2>/dev/null || true
            # Extra: Remove any remaining stopped/exited containers that match
            docker ps -a --filter \"status=exited\" --format \"{{.Names}}\" 2>/dev/null | grep -E \"(kolla|nova|neutron|cinder|glance|keystone|horizon|heat|mariadb|rabbitmq|memcached|haproxy|proxysql|fluentd|cron|openvswitch|ovn)\" | xargs -r docker rm -f 2>/dev/null || true
            docker ps -a --filter \"status=created\" --format \"{{.Names}}\" 2>/dev/null | grep -E \"(kolla|nova|neutron|cinder|glance|keystone|horizon|heat|mariadb|rabbitmq|memcached|haproxy|proxysql|fluentd|cron|openvswitch|ovn)\" | xargs -r docker rm -f 2>/dev/null || true
            # Remove kolla volumes
            docker volume ls -q 2>/dev/null | grep -E \"^(kolla_|mariadb|rabbitmq)\" | xargs -r docker volume rm -f 2>/dev/null || true
            # Clean up kolla log directories but keep the base
            rm -rf /var/log/kolla/* 2>/dev/null || true
            # Clean up libvirt directories kolla creates
            rm -rf /var/lib/docker/volumes/kolla_* 2>/dev/null || true
        '" 2>/dev/null || true
    done

    # Wait a moment for Docker to fully clean up
    log_info "Waiting for cleanup to complete..."
    sleep 5

    log_success "Stale deployment destroyed on all nodes"
}

# Fix config file formatting (remove leading tabs/spaces that break INI parsing)
# Ceph's cephadm shell generates ceph.conf with tab indentation, but Kolla's
# oslo.config parser doesn't accept leading whitespace in INI files
fix_config_formatting() {
    local file=$1
    log_info "Fixing formatting in $file..."
    # Remove leading tabs
    sed -i 's/^\t//g' "$file"
    # Remove leading spaces
    sed -i 's/^[[:space:]]*\([^[:space:]]\)/\1/g' "$file"
    # Ensure no trailing whitespace
    sed -i 's/[[:space:]]*$//' "$file"
}

# =============================================================================
# Installing Kolla-Ansible: Install Kolla-Ansible on Deployment Host
# =============================================================================

install_kolla_ansible() {
    log_section "Installing Kolla-Ansible: Installing Kolla-Ansible on Deployment Host"

    # Clean SSH known_hosts first (in case VMs were destroyed and recreated)
    clean_ssh_known_hosts

    log_info "Installing system dependencies..."
    sudo apt update
    sudo apt install -y python3-dev libffi-dev gcc libssl-dev python3-venv git

    log_info "Creating Python virtual environment..."
    if [ ! -d "$KOLLA_VENV" ]; then
        python3 -m venv "$KOLLA_VENV"
    fi
    

    log_info "Activating virtual environment and installing packages..."
    source "$KOLLA_VENV/bin/activate"

    pip install -U pip
    pip install "ansible>=8,<10"
    pip install "kolla-ansible==${KOLLA_VERSION}"
    pip install python-openstackclient

    log_info "Installing Ansible dependencies..."
    kolla-ansible install-deps

    log_info "Creating Kolla config directory..."
    sudo mkdir -p "$KOLLA_CONFIG"
    sudo chown $USER:$USER "$KOLLA_CONFIG"

    log_info "Copying example configs..."
    cp -r "$KOLLA_VENV/share/kolla-ansible/etc_examples/kolla/"* "$KOLLA_CONFIG/"

    log_info "Generating passwords..."
    kolla-genpwd

    log_success "Kolla-Ansible installation complete!"
}

# =============================================================================
# Creating Ceph Pools and Users: Create Ceph Users for OpenStack
# =============================================================================

create_ceph_users() {
    log_section "Creating Ceph Pools and Users: Creating Ceph Pools and Users for OpenStack"

    # Ceph must be running for this phase
    ensure_all_healthy

    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- ceph config set global mon_max_pg_per_osd 500 || true"
    log_info "Creating Ceph pools on ${CEPH_ADMIN_NODE}..."

    # Create pools for OpenStack services
    # Using default PG count - Ceph will auto-tune with pg_autoscaler
    log_info "Creating 'images' pool for Glance..."
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- ceph osd pool create images 32 || true"
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- ceph osd pool set images pg_autoscale_mode on || true"
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- rbd pool init images || true"

    log_info "Creating 'volumes' pool for Cinder..."
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- ceph osd pool create volumes 32 || true"
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- ceph osd pool set volumes pg_autoscale_mode on || true"
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- rbd pool init volumes || true"

    log_info "Creating 'vms' pool for Nova..."
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- ceph osd pool create vms 32 || true"
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- ceph osd pool set vms pg_autoscale_mode on || true"
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- rbd pool init vms || true"

    log_info "Creating 'backups' pool for Cinder Backup..."
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- ceph osd pool create backups 32 || true"
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- ceph osd pool set backups pg_autoscale_mode on || true"
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- rbd pool init backups || true"

    log_info "Verifying pools..."
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- ceph osd pool ls"

    log_success "Ceph pools created!"

    log_info "Creating Ceph users on ${CEPH_ADMIN_NODE}..."

    # Create users using cephadm shell and capture output
    # The key is to pipe the output to the HOST filesystem, not inside the container

    log_info "Creating client.glance user..."
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- ceph auth get-or-create client.glance \
        mon 'profile rbd' \
        osd 'profile rbd pool=images' \
        mgr 'profile rbd pool=images'" > /tmp/ceph.client.glance.keyring

    log_info "Creating client.cinder user..."
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- ceph auth get-or-create client.cinder \
        mon 'profile rbd' \
        osd 'profile rbd pool=volumes, profile rbd pool=vms, profile rbd-read-only pool=images' \
        mgr 'profile rbd pool=volumes, profile rbd pool=vms'" > /tmp/ceph.client.cinder.keyring

    log_info "Creating client.cinder-backup user..."
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- ceph auth get-or-create client.cinder-backup \
        mon 'profile rbd' \
        osd 'profile rbd pool=backups' \
        mgr 'profile rbd pool=backups'" > /tmp/ceph.client.cinder-backup.keyring

    log_info "Creating client.nova user..."
    run_on_node_sudo $CEPH_ADMIN_IP "cephadm shell -- ceph auth get-or-create client.nova \
        mon 'profile rbd' \
        osd 'profile rbd pool=vms, profile rbd pool=volumes, profile rbd-read-only pool=images' \
        mgr 'profile rbd pool=vms'" > /tmp/ceph.client.nova.keyring

    log_info "Fetching ceph.conf..."
    run_on_node_sudo $CEPH_ADMIN_IP "cat /etc/ceph/ceph.conf" > /tmp/ceph.conf

    # Fix ceph.conf formatting (remove tabs that cause parsing errors)
    # Ceph's cephadm generates ceph.conf with tab indentation like:
    #   [global]
    #   	fsid = ...
    # But Kolla's oslo.config INI parser fails with:
    #   "Unexpected continuation line: '\tfsid = ...'"
    fix_config_formatting /tmp/ceph.conf

    log_success "Ceph users created and keyrings exported!"

    # Display keyrings for verification
    log_info "Verifying keyrings..."
    echo "--- client.glance ---"
    cat /tmp/ceph.client.glance.keyring
    echo "--- client.cinder ---"
    cat /tmp/ceph.client.cinder.keyring
    echo "--- client.cinder-backup ---"
    cat /tmp/ceph.client.cinder-backup.keyring
    echo "--- client.nova ---"
    cat /tmp/ceph.client.nova.keyring
}

# =============================================================================
# Setting Up Kolla Configuration: Setup Kolla Configuration Files
# =============================================================================

setup_kolla_configs() {
    log_section "Setting Up Kolla Configuration: Setting Up Kolla Configuration Files"

    # Create directory structure
    log_info "Creating config directory structure..."
    mkdir -p "$KOLLA_CONFIG/config/glance"
    mkdir -p "$KOLLA_CONFIG/config/cinder/cinder-volume"
    mkdir -p "$KOLLA_CONFIG/config/cinder/cinder-backup"
    mkdir -p "$KOLLA_CONFIG/config/nova"

    # Helper to safely copy if source exists
    safe_copy() {
        src=$1
        dest=$2
        if [ -f "$src" ]; then
            log_info "Copying $src to $dest..."
            cp "$src" "$dest"
        else
            log_warning "Source $src missing. Assuming it's already in place."
        fi
    }

    # Copy ceph.conf to all service directories
    log_info "Copying ceph.conf to service directories..."
    safe_copy /tmp/ceph.conf "$KOLLA_CONFIG/config/glance/"
    safe_copy /tmp/ceph.conf "$KOLLA_CONFIG/config/cinder/"
    safe_copy /tmp/ceph.conf "$KOLLA_CONFIG/config/nova/"

    # Copy keyrings to appropriate directories
    log_info "Copying keyrings to service directories..."
    safe_copy /tmp/ceph.client.glance.keyring "$KOLLA_CONFIG/config/glance/"
    safe_copy /tmp/ceph.client.cinder.keyring "$KOLLA_CONFIG/config/cinder/cinder-volume/"
    safe_copy /tmp/ceph.client.cinder-backup.keyring "$KOLLA_CONFIG/config/cinder/cinder-backup/"
    safe_copy /tmp/ceph.client.cinder.keyring "$KOLLA_CONFIG/config/cinder/cinder-backup/"
    safe_copy /tmp/ceph.client.nova.keyring "$KOLLA_CONFIG/config/nova/"
    safe_copy /tmp/ceph.client.cinder.keyring "$KOLLA_CONFIG/config/nova/"

    # Fix formatting of all Ceph config files (remove tabs/spaces that break INI parsing)
    log_info "Fixing formatting of all Ceph config files..."
    for conf_file in $(find "$KOLLA_CONFIG/config" -name "ceph.conf" -o -name "*.keyring"); do
        fix_config_formatting "$conf_file"
    done

    # Create globals.yml
    log_info "Creating globals.yml..."
    cat > "$KOLLA_CONFIG/globals.yml" << EOF
---
# ========================
# 1. Base Setup
# ========================
kolla_base_distro: "ubuntu"
kolla_install_type: "source"
openstack_release: "2024.2"

# ========================
# 2. Networking (Underlay)
# ========================
# VIP on Controller Loopbacks (Anycast)
kolla_internal_vip_address: "${VIP}"
enable_keepalived: "no"

# Bind services to Host Loopbacks
api_interface_address: "{{ api_ip }}"
tunnel_interface_address: "{{ tunnel_ip }}"

# External network interface
neutron_external_interface: "dum-ex"
network_interface: "lo1"

# ========================
# 3. OVN Configuration
# ========================
neutron_plugin_agent: "ovn"
neutron_tunnel_type: "geneve"
enable_neutron_dvr: "yes"
enable_neutron_provider_networks: "yes"
neutron_ovn_distributed_fip: "yes"

# ========================
# 4. OVN BGP AGENT
# ========================
enable_neutron_bgp_dragent: "no"
enable_ovn_bgp_agent: "yes"
ovn_bgp_agent_driver: "nb_ovn_bgp_driver"

# ========================
# 5. FRR Handling
# ========================
enable_frr: "no"

# ========================
# 6. Core Services
# ========================
enable_horizon: "yes"
enable_heat: "yes"
enable_fluentd: "yes"
enable_cinder: "yes"

# ========================
# 7. Ceph Configuration (External Cluster)
# ========================
# Glance - Store images in Ceph
glance_backend_ceph: "yes"
glance_backend_file: "no"
ceph_glance_keyring: "client.glance.keyring"
ceph_glance_user: "glance"
ceph_glance_pool_name: "images"

# Cinder - Block storage with Ceph RBD
enable_cinder_backend_lvm: "no"
cinder_backend_ceph: "yes"
ceph_cinder_keyring: "client.cinder.keyring"
ceph_cinder_user: "cinder"
ceph_cinder_pool_name: "volumes"

# Cinder HA - required when multiple cinder-volume instances
cinder_cluster_name: "ceph-cinder"

# Cinder Backup to Ceph
cinder_backup_driver: "ceph"
ceph_cinder_backup_keyring: "client.cinder-backup.keyring"
ceph_cinder_backup_user: "cinder-backup"
ceph_cinder_backup_pool_name: "backups"

# Nova - Ephemeral disks and live migration with Ceph
nova_backend_ceph: "yes"
ceph_nova_keyring: "client.nova.keyring"
ceph_nova_user: "nova"
ceph_nova_pool_name: "vms"
EOF

    # Create multinode inventory
    log_info "Creating multinode inventory..."
    cat > "$KOLLA_CONFIG/multinode" << EOF
# OpenStack Multinode Inventory
# Control Plane: hypervisor-1,2,3
# Compute/Storage: hypervisor-1,2,3
# Subnet: 192.168.10.0/24

[control]
control01 ansible_host=192.168.10.11 ansible_user=ubuntu ansible_become=true api_ip=10.1.0.1 tunnel_ip=10.1.0.1
control02 ansible_host=192.168.10.12 ansible_user=ubuntu ansible_become=true api_ip=10.1.0.2 tunnel_ip=10.1.0.2
control03 ansible_host=192.168.10.13 ansible_user=ubuntu ansible_become=true api_ip=10.1.0.3 tunnel_ip=10.1.0.3

[network]
control01
control02
control03

[compute]
compute01 ansible_host=192.168.10.11 ansible_user=ubuntu ansible_become=true api_ip=10.1.0.1 tunnel_ip=10.1.0.1
compute02 ansible_host=192.168.10.12 ansible_user=ubuntu ansible_become=true api_ip=10.1.0.2 tunnel_ip=10.1.0.2
compute03 ansible_host=192.168.10.13 ansible_user=ubuntu ansible_become=true api_ip=10.1.0.3 tunnel_ip=10.1.0.3

[monitoring]
control01

# When compute nodes and control nodes use different interfaces,
# you need to comment out "api_interface" and other interfaces from the globals.yml
# and specify like below:
#compute01 neutron_external_interface=eth0 api_interface=em1 tunnel_interface=em1

[storage]
compute01
compute02

[deployment]
localhost       ansible_connection=local

[baremetal:children]
control
network
compute
storage
monitoring

# SSH key configuration for all remote hosts
[baremetal:vars]
ansible_ssh_private_key_file=~/usvf/usvf/virtual-dc/config/vdc-dc1/ssh-keys/id_rsa

[tls-backend:children]
control

# You can explicitly specify which hosts run each project by updating the
# groups in the sections below. Common services are grouped together.

[common:children]
control
network
compute
storage
monitoring

[collectd:children]
compute

[grafana:children]
monitoring

[etcd:children]
control

[influxdb:children]
monitoring

[prometheus:children]
monitoring

[telegraf:children]
compute
control
monitoring
network
storage

[hacluster:children]
control

[hacluster-remote:children]
compute

[loadbalancer:children]
network

[mariadb:children]
control

[rabbitmq:children]
control

[keystone:children]
control

[glance:children]
control

[nova:children]
control

[neutron:children]
network

[openvswitch:children]
network
compute
manila-share

[cinder:children]
control

[cloudkitty:children]
control

[memcached:children]
control

[horizon:children]
control

[swift:children]
control

[barbican:children]
control

[heat:children]
control

[ironic:children]
control

[magnum:children]
control

[mistral:children]
control

[manila:children]
control

[ceilometer:children]
control

[aodh:children]
control

[cyborg:children]
control
compute

[gnocchi:children]
control

[tacker:children]
control

[trove:children]
control

[watcher:children]
control

[octavia:children]
control

[designate:children]
control

[placement:children]
control

[bifrost:children]
deployment

[zun:children]
control

[skyline:children]
control

[redis:children]
control

[blazar:children]
control

[venus:children]
monitoring

[letsencrypt:children]
loadbalancer

# Additional control implemented here. These groups allow you to control which
# services run on which hosts at a per-service level.
#
# Word of caution: Some services are required to run on the same host to
# function appropriately. For example, neutron-metadata-agent must run on the
# same host as the l3-agent and (depending on configuration) the dhcp-agent.

# Common
[cron:children]
common

[fluentd:children]
common

[kolla-logs:children]
common

[kolla-toolbox:children]
common

[opensearch:children]
control

# Opensearch dashboards
[opensearch-dashboards:children]
opensearch

# Glance
[glance-api:children]
glance

# Nova
[nova-api:children]
nova

[nova-conductor:children]
nova

[nova-super-conductor:children]
nova

[nova-novncproxy:children]
nova

[nova-scheduler:children]
nova

[nova-spicehtml5proxy:children]
nova

[nova-compute-ironic:children]
nova

[nova-serialproxy:children]
nova

# Neutron
[neutron-server:children]
control

[neutron-dhcp-agent:children]
neutron

[neutron-l3-agent:children]
neutron

[neutron-metadata-agent:children]
neutron

[neutron-ovn-metadata-agent:children]
compute
network

[neutron-bgp-dragent:children]
neutron

[neutron-infoblox-ipam-agent:children]
neutron

[neutron-metering-agent:children]
neutron

[ironic-neutron-agent:children]
neutron

[neutron-ovn-agent:children]
compute
network

# Cinder
[cinder-api:children]
cinder

[cinder-backup:children]
storage

[cinder-scheduler:children]
cinder

[cinder-volume:children]
storage

# Cloudkitty
[cloudkitty-api:children]
cloudkitty

[cloudkitty-processor:children]
cloudkitty

# iSCSI
[iscsid:children]
compute
storage
ironic

[tgtd:children]
storage

# Manila
[manila-api:children]
manila

[manila-scheduler:children]
manila

[manila-share:children]
network

[manila-data:children]
manila

# Swift
[swift-proxy-server:children]
swift

[swift-account-server:children]
storage

[swift-container-server:children]
storage

[swift-object-server:children]
storage

# Barbican
[barbican-api:children]
barbican

[barbican-keystone-listener:children]
barbican

[barbican-worker:children]
barbican

# Heat
[heat-api:children]
heat

[heat-api-cfn:children]
heat

[heat-engine:children]
heat

# Ironic
[ironic-api:children]
ironic

[ironic-conductor:children]
ironic

[ironic-inspector:children]
ironic

[ironic-tftp:children]
ironic

[ironic-http:children]
ironic

# Magnum
[magnum-api:children]
magnum

[magnum-conductor:children]
magnum

# Mistral
[mistral-api:children]
mistral

[mistral-executor:children]
mistral

[mistral-engine:children]
mistral

[mistral-event-engine:children]
mistral

# Ceilometer
[ceilometer-central:children]
ceilometer

[ceilometer-notification:children]
ceilometer

[ceilometer-compute:children]
compute

[ceilometer-ipmi:children]
compute

# Aodh
[aodh-api:children]
aodh

[aodh-evaluator:children]
aodh

[aodh-listener:children]
aodh

[aodh-notifier:children]
aodh

# Cyborg
[cyborg-api:children]
cyborg

[cyborg-agent:children]
compute

[cyborg-conductor:children]
cyborg

# Gnocchi
[gnocchi-api:children]
gnocchi

[gnocchi-statsd:children]
gnocchi

[gnocchi-metricd:children]
gnocchi

# Trove
[trove-api:children]
trove

[trove-conductor:children]
trove

[trove-taskmanager:children]
trove

# Multipathd
[multipathd:children]
compute
storage

# Watcher
[watcher-api:children]
watcher

[watcher-engine:children]
watcher

[watcher-applier:children]
watcher

# Octavia
[octavia-api:children]
octavia

[octavia-driver-agent:children]
octavia

[octavia-health-manager:children]
octavia

[octavia-housekeeping:children]
octavia

[octavia-worker:children]
octavia

# Designate
[designate-api:children]
designate

[designate-central:children]
designate

[designate-producer:children]
designate

[designate-mdns:children]
network

[designate-worker:children]
designate

[designate-sink:children]
designate

[designate-backend-bind9:children]
designate

# Placement
[placement-api:children]
placement

# Zun
[zun-api:children]
zun

[zun-wsproxy:children]
zun

[zun-compute:children]
compute

[zun-cni-daemon:children]
compute

# Skyline
[skyline-apiserver:children]
skyline

[skyline-console:children]
skyline

# Tacker
[tacker-server:children]
tacker

[tacker-conductor:children]
tacker

# Blazar
[blazar-api:children]
blazar

[blazar-manager:children]
blazar

# Prometheus
[prometheus-node-exporter:children]
monitoring
control
compute
network
storage

[prometheus-mysqld-exporter:children]
mariadb

[prometheus-memcached-exporter:children]
memcached

[prometheus-cadvisor:children]
monitoring
control
compute
network
storage

[prometheus-alertmanager:children]
monitoring

[prometheus-openstack-exporter:children]
monitoring

[prometheus-elasticsearch-exporter:children]
opensearch

[prometheus-blackbox-exporter:children]
monitoring

[prometheus-libvirt-exporter:children]
compute

[prometheus-msteams:children]
prometheus-alertmanager

[masakari-api:children]
control

[masakari-engine:children]
control

[masakari-hostmonitor:children]
control

[masakari-instancemonitor:children]
compute

[ovn-controller:children]
ovn-controller-compute
ovn-controller-network

[ovn-controller-compute:children]
compute

[ovn-controller-network:children]
network

[ovn-database:children]
control

[ovn-northd:children]
ovn-database

[ovn-nb-db:children]
ovn-database

[ovn-sb-db:children]
ovn-database

[venus-api:children]
venus

[venus-manager:children]
venus

[letsencrypt-webserver:children]
letsencrypt

[letsencrypt-lego:children]
letsencrypt

[ovn-bgp-agent:children]
control
compute
EOF

    log_success "Kolla configuration files created!"
}

# =============================================================================
# Setting Up Anycast VIP: Setup VIP on Controllers
# =============================================================================

setup_vip() {
    log_section "Setting Up Anycast VIP: Setting Up Anycast VIP on Controllers"

    for i in "${!CONTROLLERS[@]}"; do
        node="${CONTROLLERS[$i]}"
        name="${CONTROLLER_NAMES[$i]}"
        log_info "Configuring VIP on $name ($node)..."

        # Add VIP to lo1 interface
        run_on_node_sudo $node "ip addr add ${VIP}/32 dev lo1 2>/dev/null || true"

        # Verify
        if run_on_node $node "ip addr show lo1 | grep -q $VIP"; then
            log_success "VIP configured on $name"
        else
            log_warning "VIP may already exist or failed on $name"
        fi
    done

    # Add route on deployment host
    log_info "Adding route to VIP on deployment host..."
    sudo ip route add ${VIP}/32 via ${CONTROLLERS[0]} 2>/dev/null || true

    log_success "VIP setup complete!"
}

# =============================================================================
# Installing Ceph Client: Install Ceph Client on All Nodes
# =============================================================================

install_ceph_client() {
    log_section "Installing Ceph Client: Installing Ceph Client on All Nodes"
    log_info "Waiting for apt locks..."
    for host in "${ALL_NODES[@]}"; do
        echo -n "Checking APT locks on $host... "

        if wait_for_apt_lock "$host"; then
            echo "ready"
        else
            echo "FAILED (lock held too long)"
            exit 1
        fi
    done


    for node in "${ALL_NODES[@]}"; do
        log_info "Installing ceph-common on $node..."
        run_on_node "$node" "sudo bash -c 'apt update && apt install -y ceph-common python3-rbd'"
    done

    log_success "Ceph client installed on all nodes!"
}

# =============================================================================
# Prepare Bootstrap: Stop unattended-upgrades and wait for APT locks
# =============================================================================

prepare_bootstrap() {
    log_section "Preparing nodes for bootstrap"

    log_info "Disabling unattended-upgrades and waiting for APT locks on all nodes..."

    for node in "${ALL_NODES[@]}"; do
        log_info "Preparing $node..."
        run_on_node "$node" "
            # Stop and disable unattended-upgrades
            sudo systemctl stop unattended-upgrades 2>/dev/null || true
            sudo systemctl disable unattended-upgrades 2>/dev/null || true
            sudo systemctl stop apt-daily.timer 2>/dev/null || true
            sudo systemctl stop apt-daily-upgrade.timer 2>/dev/null || true
            sudo systemctl disable apt-daily.timer 2>/dev/null || true
            sudo systemctl disable apt-daily-upgrade.timer 2>/dev/null || true

            # Wait for any running APT processes to complete (up to 2 minutes)
            echo 'Waiting for APT locks to clear...'
            for i in {1..60}; do
                if ! sudo fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock >/dev/null 2>&1; then
                    echo 'APT locks cleared'
                    break
                fi
                if [ \$i -eq 60 ]; then
                    echo 'Warning: APT lock wait timed out, proceeding anyway'
                fi
                sleep 2
            done
        " 2>/dev/null || true
    done

    log_success "All nodes prepared for bootstrap"
}

# =============================================================================
# Running Kolla-Ansible Bootstrap: Run Kolla-Ansible Bootstrap
# =============================================================================

run_bootstrap() {
    log_section "Running Kolla-Ansible Bootstrap: Running Kolla-Ansible Bootstrap"

    # ---------------------------------------------------------------
    # Step 0: Check if Ceph cluster is actually installed and running
    # ---------------------------------------------------------------
    local ceph_exists=false
    log_info "Checking if Ceph cluster is installed..."
    # Check if Docker exists AND has Ceph containers (not just /var/lib/ceph directory)
    if run_on_node "${CONTROLLERS[0]}" "command -v docker >/dev/null 2>&1 && docker ps -a --filter name=ceph 2>/dev/null | grep -q ceph" 2>/dev/null; then
        log_info "Ceph cluster detected (has running/stopped containers) - will manage during bootstrap"
        ceph_exists=true
    else
        log_info "No Ceph cluster detected (fresh nodes or no containers) - bootstrap will only handle Docker"
        ceph_exists=false
    fi

    # ---------------------------------------------------------------
    # Step 1: NUKE ceph containers if Ceph exists
    # ---------------------------------------------------------------
    if [ "$ceph_exists" = true ]; then
        log_info "Removing ceph containers and cleaning docker on all nodes..."
        for node in "${ALL_NODES[@]}"; do
            nuke_ceph_containers "$node"
        done
        sleep 3
    fi

    # ---------------------------------------------------------------
    # Step 2: Run bootstrap with retry
    # ---------------------------------------------------------------
    source "$KOLLA_VENV/bin/activate"
    cd "$KOLLA_CONFIG"

    local bootstrap_success=false
    local max_retries=2

    for retry in $(seq 0 $max_retries); do
        log_info "Running bootstrap-servers (attempt $((retry + 1))/$((max_retries + 1)))..."

        if kolla-ansible bootstrap-servers -i multinode; then
            bootstrap_success=true
            log_success "Bootstrap completed successfully!"
            break
        fi

        log_warning "Bootstrap attempt $((retry + 1)) failed"

        if [ $retry -lt $max_retries ]; then
            log_info "Recovering nodes before retry..."
            if [ "$ceph_exists" = true ]; then
                for node in "${ALL_NODES[@]}"; do
                    nuke_ceph_containers "$node"
                done
            fi
            sleep 10
        fi
    done

    if [ "$bootstrap_success" = false ]; then
        log_error "Bootstrap failed after $((max_retries + 1)) attempts"
        log_error "Check logs: ssh ubuntu@${CONTROLLERS[0]} 'sudo journalctl -xeu docker --no-pager -n 50'"
        exit 1
    fi

    # ---------------------------------------------------------------
    # Step 3: Restore Ceph if it existed before bootstrap
    # ---------------------------------------------------------------
    if [ "$ceph_exists" = true ]; then
        log_info "Restoring Ceph on all nodes (cephadm will recreate containers)..."
        for node in "${ALL_NODES[@]}"; do
            restore_ceph_after_bootstrap "$node"
        done

        # Wait for Ceph quorum (cephadm needs to recreate containers)
        log_info "Waiting for Ceph cluster to form quorum (this may take a minute)..."
        sleep 30

        # Verify Ceph
        log_info "Verifying Ceph cluster health..."
        local ceph_ok=false
        for attempt in 1 2 3 4 5; do
            if run_on_node_sudo "$CEPH_ADMIN_IP" "cephadm shell -- ceph -s" 2>/dev/null; then
                ceph_ok=true
                break
            fi
            log_warning "Ceph not ready yet (attempt $attempt/5), waiting 15s..."
            sleep 15
        done

        if [ "$ceph_ok" = false ]; then
            log_error "Ceph cluster failed to recover after bootstrap"
            log_error "Check: ssh ubuntu@${CEPH_ADMIN_IP} 'sudo cephadm shell -- ceph -s'"
            exit 1
        fi

        log_success "Bootstrap complete - Docker and Ceph both healthy!"
    else
        log_success "Bootstrap complete - Docker is healthy!"
        log_info "Next step: Install Ceph cluster before continuing OpenStack deployment"
    fi
}

# =============================================================================
# Running Kolla-Ansible Prechecks: Run Kolla-Ansible Prechecks
# =============================================================================

run_prechecks() {
    log_section "Running Kolla-Ansible Prechecks: Running Kolla-Ansible Prechecks"

    ensure_all_healthy

    source "$KOLLA_VENV/bin/activate"
    cd "$KOLLA_CONFIG"

    log_info "Running prechecks..."
    kolla-ansible prechecks -i multinode

    log_success "Prechecks passed!"
}

# =============================================================================
# Running Kolla-Ansible Deploy: Run Kolla-Ansible Deploy
# =============================================================================

run_deploy() {
    log_section "Running Kolla-Ansible Deploy: Running Kolla-Ansible Deploy"

    ensure_all_healthy

    # Pre-deployment cleanup: Remove ALL common containers to prevent handler conflicts
    # The deploy task creates containers, then handlers try to recreate them → 409 Conflict
    # Solution: Remove ALL common containers before deploy to ensure clean state
    log_info "Pre-deployment cleanup: Removing ALL common containers to prevent handler conflicts..."
    for node in "${ALL_NODES[@]}"; do
        run_on_node "$node" "sudo bash -c '
            # Remove ALL common containers (including running ones) that handlers will try to restart
            # This prevents 409 Conflict when handlers try to recreate freshly-created containers
            docker ps -a --format \"{{.Names}}\" 2>/dev/null | \
            grep -E \"^(fluentd|kolla_toolbox|cron)$\" | \
            xargs -r docker rm -f 2>/dev/null || true

            echo \"Common containers removed\"
        '" 2>/dev/null || true
    done
    log_info "Pre-deployment cleanup complete"

    source "$KOLLA_VENV/bin/activate"
    cd "$KOLLA_CONFIG"

    local max_attempts=3
    for attempt in $(seq 1 $max_attempts); do
        log_info "Starting OpenStack deployment (attempt $attempt/$max_attempts)..."

        if kolla-ansible deploy -i multinode; then
            log_success "Deployment complete!"
            return 0
        fi

        log_warning "Deploy attempt $attempt failed - checking if MariaDB recovery is needed..."

        # Check if MariaDB cluster is broken (common after interrupted deploys)
        local mariadb_broken=false
        for ctrl in "${CONTROLLERS[@]}"; do
            if run_on_node "$ctrl" "sudo docker ps -a --format '{{.Names}} {{.Status}}' 2>/dev/null | grep mariadb | grep -qi 'exited\|dead'" 2>/dev/null; then
                mariadb_broken=true
                break
            fi
        done

        # Clean up failed/stopped containers before retry
        if [ $attempt -lt $max_attempts ]; then
            log_info "Cleaning up failed containers on all nodes..."
            for node in "${ALL_NODES[@]}"; do
                run_on_node "$node" "sudo bash -c '
                    # AGGRESSIVE CLEANUP: Remove ALL matching containers (including running)
                    # This is safe because the previous deployment attempt failed
                    docker ps -a --format \"{{.Names}}\" 2>/dev/null | \
                    grep -E \"^(fluentd|kolla_toolbox|haproxy|cron|openvswitch_vswitchd|openvswitch_db)$\" | \
                    xargs -r docker rm -f 2>/dev/null || true
                '" 2>/dev/null || true
            done
        fi

        if [ "$mariadb_broken" = true ] && [ $attempt -lt $max_attempts ]; then
            log_info "MariaDB cluster appears broken - running mariadb-recovery..."
            kolla-ansible mariadb-recovery -i multinode 2>&1 || true
            sleep 10
            ensure_all_healthy
            log_info "MariaDB recovery done, retrying deploy..."
        elif [ $attempt -lt $max_attempts ]; then
            log_info "Waiting before retry..."
            ensure_all_healthy
            sleep 15
        fi
    done

    log_error "Deploy failed after $max_attempts attempts"
    exit 1
}

# =============================================================================
# Running Post-Deploy: Run Post-Deploy
# =============================================================================

run_post_deploy() {
    log_section "Running Post-Deploy: Running Post-Deploy"

    source "$KOLLA_VENV/bin/activate"
    cd "$KOLLA_CONFIG"

    log_info "Running post-deploy..."
    kolla-ansible post-deploy -i multinode

    log_success "Post-deploy complete!"
}

# =============================================================================
# Verifying Deployment: Verify Deployment
# =============================================================================

verify_deployment() {
    log_section "Verifying Deployment: Verifying Deployment"

    source "$KOLLA_VENV/bin/activate"
    source "$KOLLA_CONFIG/admin-openrc.sh"

    log_info "Testing OpenStack CLI..."
    openstack service list

    log_info "Testing Ceph connectivity from cinder_volume..."
    ssh ${SSH_OPTS} ${SSH_USER}@${COMPUTES[0]} "sudo docker exec cinder_volume ceph -s --id cinder"

    # Get Horizon password
    ADMIN_PASS=$(grep keystone_admin_password "$KOLLA_CONFIG/passwords.yml" | awk '{print $2}')

    log_success "Deployment verified!"
    echo ""
    echo "============================================================================="
    echo -e "${GREEN}OpenStack Deployment Complete!${NC}"
    echo "============================================================================="
    echo ""
    echo "Horizon Dashboard: http://${VIP}"
    echo "Username: admin"
    echo "Password: $ADMIN_PASS"
    echo ""
    echo "To use OpenStack CLI:"
    echo "  source $KOLLA_VENV/bin/activate"
    echo "  source $KOLLA_CONFIG/admin-openrc.sh"
    echo "  openstack service list"
    echo ""
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo "============================================================================="
    echo -e "${GREEN}OpenStack Deployment with Kolla-Ansible and Ceph${NC}"
    echo "============================================================================="
    echo ""
    echo "Configuration:"
    echo "  - Controllers: ${CONTROLLERS[*]}"
    echo "  - Compute:     ${COMPUTES[*]}"
    echo "  - VIP:         ${VIP}"
    echo "  - Kolla dir:   ${KOLLA_CONFIG}"
    echo ""

    # Run all phases (each is idempotent / safe to re-run)
    install_kolla_ansible
    create_ceph_users
    setup_kolla_configs
    setup_vip
    install_ceph_client
    run_bootstrap
    run_prechecks
    run_deploy
    run_post_deploy
    verify_deployment
}

# Allow running individual phases
case "${1:-}" in
    install)
        install_kolla_ansible
        ;;
    ceph-users)
        create_ceph_users
        ;;
    configs)
        setup_kolla_configs
        ;;
    vip)
        setup_vip
        ;;
    ceph-client)
        install_ceph_client
        ;;
    prepare-bootstrap)
        prepare_bootstrap
        ;;
    bootstrap)
        run_bootstrap
        ;;
    prechecks)
        run_prechecks
        ;;
    deploy)
        run_deploy
        ;;
    destroy)
        destroy_kolla
        ;;
    fresh)
        destroy_kolla
        run_bootstrap
        run_prechecks
        run_deploy
        run_post_deploy
        verify_deployment
        ;;
    post-deploy)
        run_post_deploy
        ;;
    verify)
        verify_deployment
        ;;
    *)
        main
        ;;
esac
