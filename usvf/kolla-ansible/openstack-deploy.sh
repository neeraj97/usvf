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

# Deployment host settings
KOLLA_VENV="$HOME/kolla-venv"
KOLLA_CONFIG="/etc/kolla"

# Ceph admin node (where to run ceph commands)
CEPH_ADMIN_NODE="hypervisor-1"
CEPH_ADMIN_IP="192.168.10.11"

# Controller nodes
CONTROLLERS=("192.168.10.11" "192.168.10.12" "192.168.10.13")
CONTROLLER_NAMES=("hypervisor-1" "hypervisor-2" "hypervisor-3")

# Compute nodes
COMPUTES=("192.168.10.14" "192.168.10.15")
COMPUTE_NAMES=("hypervisor-4" "hypervisor-5")

# All nodes
ALL_NODES=("${CONTROLLERS[@]}" "${COMPUTES[@]}")

# VIP for OpenStack API
VIP="10.100.0.254"

# Kolla-Ansible version
KOLLA_VERSION="18.8.0"
OPENSTACK_RELEASE="2024.1"

# SSH user for nodes
SSH_USER="ubuntu"

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
    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${node} "$@"
}

run_on_node_sudo() {
    local node=$1
    shift
    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${node} "sudo $@"
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
# Phase 1: Install Kolla-Ansible on Deployment Host
# =============================================================================

install_kolla_ansible() {
    log_section "Phase 1: Installing Kolla-Ansible on Deployment Host"

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
# Phase 2: Create Ceph Users for OpenStack
# =============================================================================

create_ceph_users() {
    log_section "Phase 2: Creating Ceph Pools and Users for OpenStack"

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
# Phase 3: Setup Kolla Configuration Files
# =============================================================================

setup_kolla_configs() {
    log_section "Phase 3: Setting Up Kolla Configuration Files"

    # Create directory structure
    log_info "Creating config directory structure..."
    mkdir -p "$KOLLA_CONFIG/config/glance"
    mkdir -p "$KOLLA_CONFIG/config/cinder/cinder-volume"
    mkdir -p "$KOLLA_CONFIG/config/cinder/cinder-backup"
    mkdir -p "$KOLLA_CONFIG/config/nova"

    # Copy ceph.conf to all service directories
    log_info "Copying ceph.conf to service directories..."
    cp /tmp/ceph.conf "$KOLLA_CONFIG/config/glance/"
    cp /tmp/ceph.conf "$KOLLA_CONFIG/config/cinder/"
    cp /tmp/ceph.conf "$KOLLA_CONFIG/config/nova/"

    # Copy keyrings to appropriate directories
    log_info "Copying keyrings to service directories..."
    cp /tmp/ceph.client.glance.keyring "$KOLLA_CONFIG/config/glance/"
    cp /tmp/ceph.client.cinder.keyring "$KOLLA_CONFIG/config/cinder/cinder-volume/"
    cp /tmp/ceph.client.cinder-backup.keyring "$KOLLA_CONFIG/config/cinder/cinder-backup/"
    cp /tmp/ceph.client.cinder.keyring "$KOLLA_CONFIG/config/cinder/cinder-backup/"  # For reading volumes
    cp /tmp/ceph.client.nova.keyring "$KOLLA_CONFIG/config/nova/"
    cp /tmp/ceph.client.cinder.keyring "$KOLLA_CONFIG/config/nova/"  # For live migration

    # Fix formatting of all Ceph config files (remove tabs/spaces that break INI parsing)
    log_info "Fixing formatting of all Ceph config files..."
    for conf_file in $(find "$KOLLA_CONFIG/config" -name "ceph.conf" -o -name "*.keyring"); do
        fix_config_formatting "$conf_file"
    done

    # Create globals.yml
    log_info "Creating globals.yml..."
    cat > "$KOLLA_CONFIG/globals.yml" << 'EOF'
---
# ========================
# 1. Base Setup
# ========================
kolla_base_distro: "ubuntu"
kolla_install_type: "source"
openstack_release: "2024.1"

# ========================
# 2. Networking (Underlay)
# ========================
# VIP on Controller Loopbacks (Anycast)
kolla_internal_vip_address: "10.100.0.254"
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
    cat > "$KOLLA_CONFIG/multinode" << 'EOF'
# OpenStack Multinode Inventory
# Control Plane: hypervisor-1,2,3
# Compute/Storage: hypervisor-4,5

[control]
control01 ansible_host=192.168.10.11 ansible_user=ubuntu ansible_become=true api_ip=10.1.0.1 tunnel_ip=10.1.0.1
control02 ansible_host=192.168.10.12 ansible_user=ubuntu ansible_become=true api_ip=10.1.0.2 tunnel_ip=10.1.0.2
control03 ansible_host=192.168.10.13 ansible_user=ubuntu ansible_become=true api_ip=10.1.0.3 tunnel_ip=10.1.0.3

[network]
control01
control02
control03

[compute]
compute01 ansible_host=192.168.10.14 ansible_user=ubuntu ansible_become=true api_ip=10.1.0.4 tunnel_ip=10.1.0.4
compute02 ansible_host=192.168.10.15 ansible_user=ubuntu ansible_become=true api_ip=10.1.0.5 tunnel_ip=10.1.0.5

[monitoring]
control01

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

[tls-backend:children]
control

# Service Groups
[common:children]
control
network
compute
storage
monitoring

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

[cinder:children]
control

[memcached:children]
control

[horizon:children]
control

[heat:children]
control

[placement:children]
control

[loadbalancer:children]
network

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

[ovn-bgp-agent:children]
control
compute

[cinder-volume:children]
storage

[cinder-backup:children]
storage
EOF

    log_success "Kolla configuration files created!"
}

# =============================================================================
# Phase 4: Setup VIP on Controllers
# =============================================================================

setup_vip() {
    log_section "Phase 4: Setting Up Anycast VIP on Controllers"

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
# Phase 5: Install Ceph Client on All Nodes
# =============================================================================

install_ceph_client() {
    log_section "Phase 5: Installing Ceph Client on All Nodes"

    for node in "${ALL_NODES[@]}"; do
        log_info "Installing ceph-common on $node..."
        run_on_node_sudo $node "apt update && apt install -y ceph-common python3-rbd"
    done

    log_success "Ceph client installed on all nodes!"
}

# =============================================================================
# Phase 6: Run Kolla-Ansible Bootstrap
# =============================================================================

run_bootstrap() {
    log_section "Phase 6: Running Kolla-Ansible Bootstrap"

    source "$KOLLA_VENV/bin/activate"
    cd "$KOLLA_CONFIG"

    log_warning "This will install Docker and configure nodes. Existing Ceph containers may restart."
    log_info "Running bootstrap-servers..."

    kolla-ansible -i multinode bootstrap-servers

    log_success "Bootstrap complete!"
}

# =============================================================================
# Phase 7: Run Kolla-Ansible Prechecks
# =============================================================================

run_prechecks() {
    log_section "Phase 7: Running Kolla-Ansible Prechecks"

    source "$KOLLA_VENV/bin/activate"
    cd "$KOLLA_CONFIG"

    log_info "Running prechecks..."
    kolla-ansible -i multinode prechecks

    log_success "Prechecks passed!"
}

# =============================================================================
# Phase 8: Run Kolla-Ansible Deploy
# =============================================================================

run_deploy() {
    log_section "Phase 8: Running Kolla-Ansible Deploy"

    source "$KOLLA_VENV/bin/activate"
    cd "$KOLLA_CONFIG"

    log_info "Starting OpenStack deployment (this takes 30-60 minutes)..."
    kolla-ansible -i multinode deploy

    log_success "Deployment complete!"
}

# =============================================================================
# Phase 9: Run Post-Deploy
# =============================================================================

run_post_deploy() {
    log_section "Phase 9: Running Post-Deploy"

    source "$KOLLA_VENV/bin/activate"
    cd "$KOLLA_CONFIG"

    log_info "Running post-deploy..."
    kolla-ansible -i multinode post-deploy

    log_success "Post-deploy complete!"
}

# =============================================================================
# Phase 10: Verify Deployment
# =============================================================================

verify_deployment() {
    log_section "Phase 10: Verifying Deployment"

    source "$KOLLA_VENV/bin/activate"
    source "$KOLLA_CONFIG/admin-openrc.sh"

    log_info "Testing OpenStack CLI..."
    openstack service list

    log_info "Testing Ceph connectivity from cinder_volume..."
    ssh ${SSH_USER}@${COMPUTES[0]} "sudo docker exec cinder_volume ceph -s --id cinder"

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
    echo "This script will deploy OpenStack with the following configuration:"
    echo "  - Controllers: hypervisor-1, hypervisor-2, hypervisor-3"
    echo "  - Compute: hypervisor-4, hypervisor-5"
    echo "  - VIP: ${VIP}"
    echo "  - Storage Backend: Ceph"
    echo ""
    echo "Press ENTER to continue or CTRL+C to abort..."
    read

    # Run all phases
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
    bootstrap)
        run_bootstrap
        ;;
    prechecks)
        run_prechecks
        ;;
    deploy)
        run_deploy
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
