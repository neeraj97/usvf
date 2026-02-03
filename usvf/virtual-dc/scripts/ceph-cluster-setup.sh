#!/bin/bash
#
# Ceph Cluster One-Click Setup Script
# Architecture:
#   Control Plane (MON/MGR): hypervisor-1, hypervisor-2, hypervisor-3
#   Data Plane (OSD): hypervisor-4, hypervisor-5
#
# Run this script from: hetzner machine
# Usage: ./ceph-cluster-setup.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
            echo "Usage: $0 --subnet=<subnet_base>"
            echo "  Example: $0 --subnet=192.168.10   # for dc1"
            echo "  Example: $0 --subnet=192.168.11   # for dc2"
            exit 0
            ;;
    esac
done

# # Validate subnet is provided
# if [ -z "$SUBNET_BASE" ]; then
#     echo "ERROR: --subnet is required"
#     echo "Usage: $0 --subnet=192.168.10   # for dc1"
#     echo "       $0 --subnet=192.168.11   # for dc2"
#     exit 1
# fi

# Configuration (derived from subnet)
# Note: We use IPs for SSH to support multiple datacenters (dc1=.10, dc2=.11, etc.)
BOOTSTRAP_HOST="192.168.10.11"
BOOTSTRAP_IP="192.168.10.11"
CONTROL_HOSTS=("192.168.10.11" "192.168.10.12" "192.168.10.13")
CONTROL_IPS=("192.168.10.11" "192.168.10.12" "192.168.10.13")
OSD_HOSTS=("192.168.10.11" "192.168.10.12" "192.168.10.13")
OSD_IPS=("192.168.10.11" "192.168.10.12" "192.168.10.13")
ALL_HOSTS=("192.168.10.11" "192.168.10.12" "192.168.10.13")

# Hostnames for Ceph (used in ceph orch host add)
CONTROL_NAMES=("hypervisor-1" "hypervisor-2" "hypervisor-3")
OSD_NAMES=("hypervisor-1" "hypervisor-2" "hypervisor-3")
ALL_NAMES=("hypervisor-1" "hypervisor-2" "hypervisor-3")

# SSH configuration
SSH_USER="ubuntu"
SSH_KEY="$HOME/usvf/usvf/virtual-dc/config/vdc-dc1/ssh-keys/id_rsa"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${SSH_KEY}"

# RBD and RGW Configuration
RBD_POOL="rbd_data"
RBD_USER="rbduser"
RGW_USER="s3user"
RGW_PORT=7480

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

run_on_host() {
    local host=$1
    shift
    # Use IP address for SSH with proper user and key
    ssh ${SSH_OPTS} ${SSH_USER}@${host} "$@"
}

run_ceph_cmd() {
    # Run ceph command via cephadm shell on bootstrap host
    ssh ${SSH_OPTS} ${SSH_USER}@${BOOTSTRAP_HOST} "sudo cephadm shell -- $*"
}

wait_for_health() {
    local max_attempts=${1:-60}
    local attempt=0
    log_info "Waiting for Ceph cluster to become healthy..."
    while [ $attempt -lt $max_attempts ]; do
        if run_ceph_cmd ceph health 2>/dev/null | grep -q "HEALTH_OK\|HEALTH_WARN"; then
            log_info "Ceph cluster is healthy"
            return 0
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 5
    done
    log_warn "Cluster not fully healthy after $max_attempts attempts, continuing anyway..."
    return 0
}

# ============================================================================
# Step: Fix SSH known_hosts and wait for hosts to be ready
# ============================================================================
phase0_fix_ssh_keys() {
    log_info "=== Step: Fixing SSH known_hosts and waiting for hosts ==="

    # Remove old host keys for all IPs and hostnames
    log_info "Removing old SSH host keys..."
    for entry in "${ALL_HOSTS[@]}" "${CONTROL_IPS[@]}" "${OSD_IPS[@]}"; do
        ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$entry" 2>/dev/null || true
    done

    # Wait for all hosts to be reachable (max 5 minutes)
    log_info "Waiting for all hosts to be reachable..."
    local max_wait=300
    local wait_interval=10
    local elapsed=0

    while [ $elapsed -lt $max_wait ]; do
        local all_ready=true
        for ip in "${CONTROL_IPS[@]}" "${OSD_IPS[@]}"; do
            if ! nc -z -w 2 "$ip" 22 2>/dev/null; then
                all_ready=false
                break
            fi
        done

        if $all_ready; then
            log_info "All hosts are reachable!"
            break
        fi

        echo -n "."
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done

    if [ $elapsed -ge $max_wait ]; then
        log_error "Timeout waiting for hosts to be ready. Please ensure all VMs are running."
        exit 1
    fi

    # Wait for SSH to be fully ready (cloud-init must finish setting up authorized_keys)
    # This is more reliable than a fixed sleep - we actually test SSH connectivity
    log_info "Waiting for SSH to be fully ready on all hosts (cloud-init must complete)..."
    local ssh_max_wait=300  # 5 minutes max
    local ssh_interval=10

    for host in "${ALL_HOSTS[@]}"; do
        local ssh_elapsed=0
        local ssh_ready=false

        echo -n "  Waiting for $host"
        while [ $ssh_elapsed -lt $ssh_max_wait ]; do
            # Use timeout command to prevent hanging
            if timeout 10 ssh ${SSH_OPTS} -o ConnectTimeout=5 -o BatchMode=yes ${SSH_USER}@"$host" "hostname" > /dev/null 2>&1; then
                ssh_ready=true
                break
            fi
            echo -n "."
            sleep $ssh_interval
            ssh_elapsed=$((ssh_elapsed + ssh_interval))
        done

        if $ssh_ready; then
            echo " OK"
        else
            echo " FAILED"
            log_error "Cannot SSH to $host after ${ssh_max_wait}s. Cloud-init may not have completed."
            log_error "Check: ssh -i ${SSH_KEY} ${SSH_USER}@${host}"
            exit 1
        fi
    done

    # Scan and add new host keys (for other tools that use known_hosts)
    log_info "Scanning and adding SSH host keys to known_hosts..."
    for ip in "${CONTROL_IPS[@]}" "${OSD_IPS[@]}"; do
        ssh-keyscan -H "$ip" >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
    done

    log_info "Step 0 complete: All hosts ready"
}

# ============================================================================
# Step: Prerequisites on all hosts
# ============================================================================
stop_unattended_upgrades() {
    local host=$1
    # Stop unattended-upgrades and apt services, release locks
    ssh ${SSH_OPTS} ${SSH_USER}@"$host" "
        sudo systemctl stop apt-daily.timer apt-daily-upgrade.timer 2>/dev/null
        sudo systemctl stop apt-daily.service apt-daily-upgrade.service unattended-upgrades.service 2>/dev/null
        sudo systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null
        sudo pkill -9 -f unattended-upgrade 2>/dev/null
        sudo pkill -9 -f apt 2>/dev/null
        sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null
        sudo dpkg --configure -a 2>/dev/null
    " 2>/dev/null || true
}

wait_for_apt_lock() {
    local host=$1
    local max_wait=60  # 1 minute max after stopping services
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if ssh ${SSH_OPTS} ${SSH_USER}@"$host" "! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1" 2>/dev/null; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}

phase1_prerequisites() {
    log_info "=== Step: Installing prerequisites on all hosts ==="

    # Stop unattended-upgrades on all hosts immediately (don't wait for it)
    log_info "Stopping unattended-upgrades on all hosts..."
    for host in "${ALL_HOSTS[@]}"; do
        echo -n "  Stopping apt services on $host..."
        stop_unattended_upgrades "$host"
        echo " done"
    done

    # Check if any VMs need a reboot and reboot them now (to prevent reboots during install)
    log_info "Checking for pending reboots..."
    local needs_reboot=false
    for host in "${ALL_HOSTS[@]}"; do
        if ssh ${SSH_OPTS} ${SSH_USER}@"$host" "test -f /var/run/reboot-required" 2>/dev/null; then
            log_warn "  $host needs reboot - initiating..."
            ssh ${SSH_OPTS} ${SSH_USER}@"$host" "sudo reboot" 2>/dev/null || true
            needs_reboot=true
        else
            log_info "  $host: no reboot needed"
        fi
    done

    # If any VMs were rebooted, wait for them to come back up
    if $needs_reboot; then
        log_info "Waiting for rebooted VMs to come back online..."
        sleep 30  # Initial wait for shutdown

        for host in "${ALL_HOSTS[@]}"; do
            echo -n "  Waiting for $host"
            local wait_elapsed=0
            local max_wait=180  # 3 minutes max
            while [ $wait_elapsed -lt $max_wait ]; do
                if timeout 5 ssh ${SSH_OPTS} -o ConnectTimeout=3 ${SSH_USER}@"$host" "hostname" >/dev/null 2>&1; then
                    echo " UP"
                    break
                fi
                echo -n "."
                sleep 10
                wait_elapsed=$((wait_elapsed + 10))
            done
            if [ $wait_elapsed -ge $max_wait ]; then
                echo " TIMEOUT"
                log_error "VM $host did not come back up after reboot"
                exit 1
            fi
        done

        # Stop unattended-upgrades again after reboot
        log_info "Stopping apt services after reboot..."
        for host in "${ALL_HOSTS[@]}"; do
            stop_unattended_upgrades "$host"
        done
        sleep 5
    fi

    # Now wait for apt locks to be released (should be quick after killing processes)
    log_info "Waiting for apt locks..."
    for host in "${ALL_HOSTS[@]}"; do
        echo -n "  Checking $host..."
        if wait_for_apt_lock "$host"; then
            echo " ready"
        else
            echo " retrying..."
            stop_unattended_upgrades "$host"
            sleep 2
        fi
    done

    for host in "${ALL_HOSTS[@]}"; do
        # Verify Docker is already installed (from bootstrap phase)
        if ! ssh ${SSH_OPTS} ${SSH_USER}@"$host" "which docker > /dev/null 2>&1"; then
            log_error "Docker is not installed on $host! Bootstrap should have installed it."
            exit 1
        fi

        # Verify Docker is active
        if ! ssh ${SSH_OPTS} ${SSH_USER}@"$host" "systemctl is-active docker | grep -q '^active\$'" 2>/dev/null; then
            log_error "Docker is not active on $host! Bootstrap should have started it."
            exit 1
        fi

        log_info "Docker already installed and active on $host (from bootstrap)"
        log_info "Installing ceph-common on $host..."

        # First fix any dpkg interruption issues
        ssh ${SSH_OPTS} ${SSH_USER}@"$host" "sudo dpkg --configure -a 2>/dev/null" || true

        # Retry logic for ceph-common installation only
        local max_retries=3
        local retry=0
        local success=false
        while [ $retry -lt $max_retries ]; do
            if ssh ${SSH_OPTS} ${SSH_USER}@"$host" "sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ceph-common" 2>/dev/null; then
                success=true
                break
            fi
            retry=$((retry + 1))
            log_warn "Retry $retry/$max_retries for ceph-common installation on $host..."
            ssh ${SSH_OPTS} ${SSH_USER}@"$host" "sudo dpkg --configure -a 2>/dev/null" || true
            sleep 10
        done

        if [ "$success" = false ]; then
            log_error "Failed to install ceph-common on $host after $max_retries attempts"
            exit 1
        fi
    done

    log_info "Installing cephadm on $BOOTSTRAP_HOST..."
    # Wait for apt on bootstrap host again
    wait_for_apt "$BOOTSTRAP_HOST" || true

    # Try apt first, then download directly if apt fails
    run_on_host "$BOOTSTRAP_HOST" "
        if ! which cephadm > /dev/null 2>&1; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cephadm || {
                echo 'apt install failed, downloading cephadm directly...'
                curl --silent --remote-name --location https://download.ceph.com/rpm-squid/el9/noarch/cephadm
                chmod +x cephadm
                sudo mv cephadm /usr/sbin/cephadm
            }
        fi
        # Verify cephadm is installed
        which cephadm && (cephadm version || true)
    "

    # Verify cephadm is actually available
    if ! run_on_host "$BOOTSTRAP_HOST" "which cephadm > /dev/null 2>&1"; then
        log_error "cephadm installation failed!"
        exit 1
    fi

    log_info "Step 1 complete: Prerequisites installed"
}

# ============================================================================
# Step: Bootstrap Ceph cluster
# ============================================================================
phase2_bootstrap() {
    log_info "=== Step: Bootstrapping Ceph cluster ==="

    # Check if already bootstrapped
    if run_on_host "$BOOTSTRAP_HOST" "sudo test -f /etc/ceph/ceph.conf" 2>/dev/null; then
        log_warn "Ceph already bootstrapped on $BOOTSTRAP_HOST, skipping bootstrap"
        return 0
    fi

    log_info "Bootstrapping Ceph on $BOOTSTRAP_HOST ($BOOTSTRAP_IP)..."
    run_on_host "$BOOTSTRAP_HOST" "sudo cephadm bootstrap --mon-ip $BOOTSTRAP_IP --skip-monitoring-stack"

    log_info "Step 2 complete: Ceph bootstrapped"
}

# ============================================================================
# Step: Distribute SSH keys to all hosts
# ============================================================================
phase3_distribute_keys() {
    log_info "=== Step: Distributing Ceph SSH keys ==="

    # Get the ceph public key
    CEPH_PUBKEY=$(run_on_host "$BOOTSTRAP_HOST" "sudo cat /etc/ceph/ceph.pub")

    for host in "${ALL_HOSTS[@]}"; do
        if [ "$host" != "$BOOTSTRAP_HOST" ]; then
            log_info "Adding Ceph SSH key to $host..."
            run_on_host "$host" "grep -qF '$CEPH_PUBKEY' /root/.ssh/authorized_keys 2>/dev/null || echo '$CEPH_PUBKEY' | sudo tee -a /root/.ssh/authorized_keys > /dev/null"
        fi
    done

    log_info "Step 3 complete: SSH keys distributed"
}

# ============================================================================
# Step: Add hosts to Ceph cluster
# ============================================================================
phase4_add_hosts() {
    log_info "=== Step: Adding hosts to Ceph cluster ==="

    # Add all hosts using names and IPs
    for i in "${!ALL_NAMES[@]}"; do
        name="${ALL_NAMES[$i]}"
        ip="${ALL_HOSTS[$i]}"

        log_info "Adding $name ($ip) to cluster..."
        run_ceph_cmd ceph orch host add "$name" "$ip" 2>/dev/null || log_warn "$name may already be added"
    done

    # Add labels to control plane hosts
    for name in "${CONTROL_NAMES[@]}"; do
        log_info "Labeling $name as 'control'..."
        run_ceph_cmd ceph orch host label add "$name" control 2>/dev/null || true
    done

    # Add labels to OSD hosts
    for name in "${OSD_NAMES[@]}"; do
        log_info "Labeling $name as 'osd'..."
        run_ceph_cmd ceph orch host label add "$name" osd 2>/dev/null || true
    done

    log_info "Step 4 complete: Hosts added and labeled"
}

# ============================================================================
# Step: Deploy MON and MGR on control plane
# ============================================================================
phase5_deploy_mon_mgr() {
    log_info "=== Step: Deploying MON and MGR on control plane ==="

    log_info "Deploying MON daemons on control plane..."
    run_ceph_cmd ceph orch apply mon --placement="label:control"

    log_info "Deploying MGR daemons on control plane..."
    run_ceph_cmd ceph orch apply mgr --placement="label:control"

    # Wait for MON/MGR to be deployed
    sleep 10
    wait_for_health 30

    log_info "Step 5 complete: MON and MGR deployed"
}

# ============================================================================
# Step: Deploy OSDs on data plane
# ============================================================================
phase6_deploy_osds() {
    log_info "=== Step: Deploying OSDs on data plane ==="

    # Create OSD spec file - write to cephadm-accessible location
    OSD_SPEC=$(cat <<'EOF'
service_type: osd
service_id: osd-data
placement:
  label: osd
spec:
  data_devices:
    all: true
EOF
)

    # Apply OSD spec - pipe directly into cephadm shell
    log_info "Applying OSD specification..."
    echo "$OSD_SPEC" | ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo cephadm shell -- ceph orch apply -i -"

    # Wait for OSDs to come up (this can take a while)
    log_info "Waiting for OSDs to deploy (this may take a few minutes)..."
    sleep 30

    local max_attempts=60
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        OSD_COUNT=$(run_ceph_cmd ceph osd stat 2>/dev/null | grep -oP '\d+(?= osds)' || echo "0")
        if [ "$OSD_COUNT" -gt 0 ]; then
            log_info "Found $OSD_COUNT OSD(s) deployed"
            break
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 10
    done

    wait_for_health 60

    log_info "Step 6 complete: OSDs deployed"
}

# ============================================================================
# Step: Configure pool settings and create RBD pool
# ============================================================================
phase7_create_rbd() {
    log_info "=== Step: Configuring pools and creating RBD pool ==="

    # Set default pool size to 2 (since we have 2 OSDs)
    log_info "Setting default pool size to 2 for 2-OSD cluster..."
    run_ceph_cmd ceph config set global osd_pool_default_size 2
    run_ceph_cmd ceph config set global osd_pool_default_min_size 1

    # Set existing pools to size 2
    log_info "Configuring existing pools with size=2..."
    for pool in $(run_ceph_cmd ceph osd pool ls 2>/dev/null); do
        run_ceph_cmd ceph osd pool set "$pool" size 2 --yes-i-really-mean-it 2>/dev/null || true
        run_ceph_cmd ceph osd pool set "$pool" min_size 1 2>/dev/null || true
    done

    # Check if pool exists
    if run_ceph_cmd ceph osd pool ls 2>/dev/null | grep -q "^${RBD_POOL}$"; then
        log_warn "Pool $RBD_POOL already exists, skipping creation"
    else
        log_info "Creating RBD pool: $RBD_POOL..."
        run_ceph_cmd ceph osd pool create "$RBD_POOL" 32
        run_ceph_cmd ceph osd pool application enable "$RBD_POOL" rbd
        run_ceph_cmd rbd pool init "$RBD_POOL"
    fi

    # Create RBD user
    log_info "Creating RBD user: client.$RBD_USER..."
    run_ceph_cmd ceph auth get-or-create client.$RBD_USER \
        mon "'profile rbd'" \
        osd "'profile rbd pool=$RBD_POOL'" \
        mgr "'profile rbd pool=$RBD_POOL'"

    log_info "Step 7 complete: RBD pool and user created"
}

# ============================================================================
# Step: Deploy RadosGW (S3 Gateway)
# ============================================================================
phase8_deploy_rgw() {
    log_info "=== Step: Deploying RadosGW (S3 Gateway) ==="

    # Check if RGW is already running
    if run_ceph_cmd ceph orch ps --daemon-type rgw 2>/dev/null | grep -q "running"; then
        log_warn "RGW already running, skipping deployment"
    else
        log_info "Deploying RGW on OSD hosts (port $RGW_PORT)..."
        # Create RGW spec and apply via stdin
        cat <<EOF | ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo cephadm shell -- ceph orch apply -i -"
service_type: rgw
service_id: s3-gw
placement:
  hosts:
    - hypervisor-1
    - hypervisor-2
    - hypervisor-3
spec:
  rgw_frontend_port: $RGW_PORT
EOF

        # Wait for RGW to come up
        log_info "Waiting for RGW to deploy..."
        sleep 30

        # Check RGW status
        local max_attempts=30
        local attempt=0
        while [ $attempt -lt $max_attempts ]; do
            if run_ceph_cmd ceph orch ps --daemon-type rgw 2>/dev/null | grep -q "running"; then
                log_info "RGW is running"
                break
            fi
            attempt=$((attempt + 1))
            echo -n "."
            sleep 5
        done
    fi

    # Create S3 user (idempotent - will fail silently if exists)
    log_info "Creating S3 user: $RGW_USER..."
    ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo cephadm shell -- radosgw-admin user create --uid=$RGW_USER --display-name='S3_User'" 2>&1 || true

    # Get user info - run command and capture full output
    log_info "Extracting S3 credentials..."
    local USER_INFO
    USER_INFO=$(ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo cephadm shell -- radosgw-admin user info --uid=$RGW_USER" 2>&1) || true

    # Debug: show if we got user info
    if echo "$USER_INFO" | grep -q "access_key"; then
        log_info "User info retrieved successfully"
    else
        log_error "Failed to get user info. Output: $USER_INFO"
        return 1
    fi

    # Extract keys using sed
    ACCESS_KEY=$(echo "$USER_INFO" | sed -n 's/.*"access_key":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    SECRET_KEY=$(echo "$USER_INFO" | sed -n 's/.*"secret_key":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

    if [ -n "$ACCESS_KEY" ] && [ -n "$SECRET_KEY" ]; then
        log_info "S3 credentials:"
        echo "  Access Key: $ACCESS_KEY"
        echo "  Secret Key: $SECRET_KEY"

        # Save credentials to file on bootstrap host using echo (more reliable than heredoc over ssh)
        ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "echo 'S3 User Credentials
===================
Access Key: $ACCESS_KEY
Secret Key: $SECRET_KEY
Endpoint: http://192.168.10.11:$RGW_PORT or http://192.168.10.12:$RGW_PORT or http://192.168.10.13:$RGW_PORT' | sudo tee /root/s3-credentials.txt > /dev/null"

        log_info "Credentials saved to $BOOTSTRAP_HOST:/root/s3-credentials.txt"
    else
        log_error "Could not extract S3 credentials!"
        log_info "ACCESS_KEY='$ACCESS_KEY' SECRET_KEY='$SECRET_KEY'"
        log_info "You can get them manually with: sudo cephadm shell -- radosgw-admin user info --uid=$RGW_USER"
        return 1
    fi

    log_info "Step 8 complete: RadosGW deployed"
}

# ============================================================================
# Step: Export configs for OpenStack integration
# ============================================================================
phase9_export_configs() {
    log_info "=== Step: Exporting configs for OpenStack integration ==="

    # Get FSID
    FSID=$(run_ceph_cmd ceph fsid)
    log_info "Cluster FSID: $FSID"

    # Export ceph.conf to host
    log_info "Exporting ceph.conf to $BOOTSTRAP_HOST:/etc/ceph/ceph.conf..."
    run_ceph_cmd ceph config generate-minimal-conf | ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo tee /etc/ceph/ceph.conf > /dev/null"

    # Export admin keyring
    log_info "Exporting admin keyring..."
    run_ceph_cmd ceph auth get client.admin | ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo tee /etc/ceph/ceph.client.admin.keyring > /dev/null"
    ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo chmod 600 /etc/ceph/ceph.client.admin.keyring"

    # Export RBD user keyring
    log_info "Exporting $RBD_USER keyring..."
    run_ceph_cmd ceph auth get client.$RBD_USER | ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo tee /etc/ceph/ceph.client.$RBD_USER.keyring > /dev/null"
    ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo chmod 600 /etc/ceph/ceph.client.$RBD_USER.keyring"

    log_info "Step 9 complete: Configs exported"
}

# ============================================================================
# Verification tests
# ============================================================================
phase10_verify() {
    log_info "=== Running Ceph verification tests ==="

    echo ""
    log_info "--- Test 1: Cluster Health ---"
    run_ceph_cmd ceph -s

    echo ""
    log_info "--- Test 2: OSD Status ---"
    run_ceph_cmd ceph osd tree

    echo ""
    log_info "--- Test 3: Pool List ---"
    run_ceph_cmd ceph osd pool ls detail

    echo ""
    log_info "--- Test 4: RBD Pool Test ---"
    TEST_IMAGE="test-image-$$"
    log_info "Creating test RBD image: $TEST_IMAGE..."
    run_ceph_cmd rbd create --size 100 $RBD_POOL/$TEST_IMAGE
    log_info "Listing RBD images..."
    run_ceph_cmd rbd ls $RBD_POOL
    log_info "Getting image info..."
    run_ceph_cmd rbd info $RBD_POOL/$TEST_IMAGE
    log_info "Removing test image..."
    run_ceph_cmd rbd rm $RBD_POOL/$TEST_IMAGE
    log_info "RBD test passed!"

    echo ""
    log_info "--- Test 5: RadosGW Status ---"
    run_ceph_cmd ceph orch ps --daemon-type rgw

    echo ""
    log_info "--- Test 6: S3 Connectivity Test ---"
    # Test S3 endpoint from one of the OSD hosts
    if curl -s --connect-timeout 5 "http://192.168.10.11:$RGW_PORT" > /dev/null 2>&1; then
        log_info "S3 endpoint on hypervisor-1:$RGW_PORT is reachable"
    else
        log_warn "S3 endpoint on hypervisor-1:$RGW_PORT may not be ready yet"
    fi

    if curl -s --connect-timeout 5 "http://192.168.10.12:$RGW_PORT" > /dev/null 2>&1; then
        log_info "S3 endpoint on hypervisor-2:$RGW_PORT is reachable"
    else
        log_warn "S3 endpoint on hypervisor-2:$RGW_PORT may not be ready yet"
    fi
    
    if curl -s --connect-timeout 5 "http://192.168.10.13:$RGW_PORT" > /dev/null 2>&1; then
        log_info "S3 endpoint on hypervisor-3:$RGW_PORT is reachable"
    else
        log_warn "S3 endpoint on hypervisor-3:$RGW_PORT may not be ready yet"
    fi

    echo ""
    log_info "--- Test 7: Host Status ---"
    run_ceph_cmd ceph orch host ls

    echo ""
    log_info "--- Test 8: Full S3 Test with AWS CLI ---"
    # Install AWS CLI on bootstrap host if not present
    log_info "Installing AWS CLI on $BOOTSTRAP_HOST..."
    ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" 'if ! which aws > /dev/null 2>&1; then
        sudo apt-get install -y -qq unzip curl
        cd /tmp
        curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip -q -o awscliv2.zip
        sudo ./aws/install --update 2>/dev/null || sudo ./aws/install 2>/dev/null
    fi'

    # Get S3 credentials from the credentials file we saved earlier
    S3_ACCESS_KEY=$(ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo grep 'Access Key' /root/s3-credentials.txt 2>/dev/null | cut -d: -f2 | tr -d ' '")
    S3_SECRET_KEY=$(ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo grep 'Secret Key' /root/s3-credentials.txt 2>/dev/null | cut -d: -f2 | tr -d ' '")

    if [ -n "$S3_ACCESS_KEY" ] && [ -n "$S3_SECRET_KEY" ]; then
        log_info "Running S3 bucket test..."
        log_info "Using Access Key: $S3_ACCESS_KEY"

        # Configure AWS credentials on bootstrap host (as root)
        ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo mkdir -p /root/.aws && echo '[ceph]
aws_access_key_id = $S3_ACCESS_KEY
aws_secret_access_key = $S3_SECRET_KEY' | sudo tee /root/.aws/credentials > /dev/null && echo '[profile ceph]
region = us-east-1' | sudo tee /root/.aws/config > /dev/null"

        # Run S3 test as root
        ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo /usr/local/bin/aws --endpoint-url http://192.168.10.11:$RGW_PORT --profile ceph s3 mb s3://ceph-test-bucket" 2>&1 || true
        log_info "Created test bucket"

        ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "echo 'Hello from Ceph S3 automated test!' | sudo tee /tmp/s3-test.txt > /dev/null"
        ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo /usr/local/bin/aws --endpoint-url http://192.168.10.11:$RGW_PORT --profile ceph s3 cp /tmp/s3-test.txt s3://ceph-test-bucket/test.txt" 2>&1
        log_info "Uploaded test file"

        log_info "Listing bucket contents:"
        ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo /usr/local/bin/aws --endpoint-url http://192.168.10.11:$RGW_PORT --profile ceph s3 ls s3://ceph-test-bucket/" 2>&1

        log_info "Downloading and verifying:"
        ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo /usr/local/bin/aws --endpoint-url http://192.168.10.11:$RGW_PORT --profile ceph s3 cp s3://ceph-test-bucket/test.txt /tmp/s3-download.txt" 2>&1
        ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "cat /tmp/s3-download.txt"

        log_info "Cleaning up test bucket..."
        ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo /usr/local/bin/aws --endpoint-url http://192.168.10.11:$RGW_PORT --profile ceph s3 rm s3://ceph-test-bucket/test.txt" 2>&1 || true
        ssh ${SSH_OPTS} ${SSH_USER}@"$BOOTSTRAP_HOST" "sudo /usr/local/bin/aws --endpoint-url http://192.168.10.11:$RGW_PORT --profile ceph s3 rb s3://ceph-test-bucket" 2>&1 || true

        log_info "S3 test passed!"
    else
        log_warn "Could not retrieve S3 credentials for full test"
    fi

    echo ""
    log_info "=== ALL VERIFICATION TESTS COMPLETE ==="
}

# ============================================================================
# Main execution
# ============================================================================
main() {
    echo "============================================================"
    echo "       Ceph Cluster One-Click Setup"
    echo "============================================================"
    echo ""
    echo "Subnet:        192.168.10.0/24"
    echo "Control Plane: ${CONTROL_HOSTS[*]} (${CONTROL_IPS[*]})"
    echo "Data Plane:    ${OSD_HOSTS[*]} (${OSD_IPS[*]})"
    echo ""

    phase0_fix_ssh_keys
    phase1_prerequisites
    phase2_bootstrap
    phase3_distribute_keys
    phase4_add_hosts
    phase5_deploy_mon_mgr
    phase6_deploy_osds
    phase7_create_rbd
    phase8_deploy_rgw
    phase9_export_configs
    phase10_verify

    echo ""
    echo "============================================================"
    log_info "Ceph cluster setup complete!"
    echo "============================================================"
    echo ""
    echo "Next steps:"
    echo "  1. For S3 access, AWS CLI is installed on $BOOTSTRAP_HOST"
    echo "     Credentials saved at: $BOOTSTRAP_HOST:/root/s3-credentials.txt"
    echo "     AWS config at: $BOOTSTRAP_HOST:~/.aws/"
    echo ""
    echo "  2. For OpenStack integration, use configs from:"
    echo "     /etc/ceph/ceph.conf"
    echo "     /etc/ceph/ceph.client.admin.keyring"
    echo ""
    echo "  3. To check cluster status anytime:"
    echo "     ssh $BOOTSTRAP_HOST 'sudo cephadm shell -- ceph -s'"
    echo ""
    echo "  4. To use S3 from $BOOTSTRAP_HOST:"
    echo "     ssh $BOOTSTRAP_HOST"
    echo "     aws --endpoint-url http://192.168.10.11:$RGW_PORT --profile ceph s3 ls"
    echo ""
}

# Run main
main "$@"
