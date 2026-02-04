#!/bin/bash
#
# Complete Unified Deployment Script
# Deploys both Ceph and OpenStack on fresh hypervisors
#
# This script combines ceph-cluster-setup.sh and openstack-deploy.sh
# in the correct sequence for a fresh deployment.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSTACK_SCRIPT="$SCRIPT_DIR/openstack-deploy.sh"
CEPH_SCRIPT="$(dirname "$SCRIPT_DIR")/scripts/ceph-cluster-setup.sh"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_section() { echo -e "\n${BLUE}=============================================================================${NC}"; echo -e "${GREEN}$1${NC}"; echo -e "${BLUE}=============================================================================${NC}\n"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# PHASE 1: OpenStack Prerequisites (NO Ceph yet)
# =============================================================================
phase1_openstack_prereqs() {
    log_section "PHASE 1: OpenStack Prerequisites"

    log_info "Step 1.1: Installing Kolla-Ansible..."
    bash "$OPENSTACK_SCRIPT" install

    log_info "Step 1.2: Setting up VIP on controllers..."
    bash "$OPENSTACK_SCRIPT" vip

    log_success "OpenStack prerequisites complete"
    log_info "Note: Ceph client packages will be installed after Ceph cluster setup"
}

# =============================================================================
# PHASE 2: Create Kolla Configs (WITHOUT Ceph configs)
# =============================================================================
phase2_create_base_configs() {
    log_section "PHASE 2: Creating Base Kolla Configurations"

    log_info "Creating globals.yml and multinode inventory..."
    log_info "Note: Ceph configs will be added after Ceph installation"

    # We'll use a modified version of setup_kolla_configs that skips Ceph file copying
    bash "$OPENSTACK_SCRIPT" configs || true

    log_success "Base Kolla configurations created"
}

# =============================================================================
# PHASE 3: OpenStack Bootstrap (Docker setup)
# =============================================================================
phase3_openstack_bootstrap() {
    log_section "PHASE 3: OpenStack Bootstrap"

    # Prevent APT lock race conditions during bootstrap
    log_info "Preparing nodes for bootstrap (disabling unattended-upgrades and waiting for APT locks)..."
    bash "$OPENSTACK_SCRIPT" prepare-bootstrap

    log_info "Running Kolla-Ansible bootstrap..."
    log_info "This will install and configure Docker on all nodes"

    bash "$OPENSTACK_SCRIPT" bootstrap

    # Re-add VIP after bootstrap (in case nodes rebooted during bootstrap)
    log_info "Re-configuring VIP on controllers (in case of reboot during bootstrap)..."
    bash "$OPENSTACK_SCRIPT" vip

    log_success "OpenStack bootstrap complete - Docker is configured"
}

# =============================================================================
# PHASE 4: Ceph Cluster Installation
# =============================================================================
phase4_install_ceph() {
    log_section "PHASE 4: Ceph Cluster Installation"

    log_info "Installing complete Ceph cluster..."
    log_info "This includes: MON, MGR, OSDs, RadosGW, pools"

    if [ ! -f "$CEPH_SCRIPT" ]; then
        log_error "Ceph installation script not found at: $CEPH_SCRIPT"
        exit 1
    fi

    bash "$CEPH_SCRIPT"

    log_success "Ceph cluster installation complete"
}

# =============================================================================
# PHASE 5: Install Ceph Client Packages
# =============================================================================
phase5_install_ceph_client() {
    log_section "PHASE 5: Installing Ceph Client Packages"

    log_info "Installing ceph-common and python3-rbd on all OpenStack nodes..."

    bash "$OPENSTACK_SCRIPT" ceph-client

    log_success "Ceph client packages installed"
}

# =============================================================================
# PHASE 6: Create OpenStack Ceph Users
# =============================================================================
phase6_create_ceph_users() {
    log_section "PHASE 6: Creating OpenStack Ceph Users"

    log_info "Creating Ceph users: client.glance, client.cinder, client.nova, client.cinder-backup..."

    bash "$OPENSTACK_SCRIPT" ceph-users

    log_success "OpenStack Ceph users created"
}

# =============================================================================
# PHASE 7: Distribute Ceph Configs to Kolla
# =============================================================================
phase7_distribute_ceph_configs() {
    log_section "PHASE 7: Distributing Ceph Configs to Kolla"

    log_info "Distributing ceph.conf and keyrings to Kolla config directories..."

    # Note: Ceph configs and keyrings were already created in Phase 6 and saved to /tmp/
    # on the deployment host. Now we just need to distribute them to Kolla config dirs.

    log_info "Running config setup to copy Ceph files from /tmp/ to Kolla directories..."
    bash "$OPENSTACK_SCRIPT" configs

    log_success "Ceph configs distributed to Kolla"
}

# =============================================================================
# PHASE 8: OpenStack Deployment
# =============================================================================
phase8_openstack_deploy() {
    log_section "PHASE 8: OpenStack Deployment"

    log_info "Step 8.1: Running prechecks..."
    bash "$OPENSTACK_SCRIPT" prechecks

    log_info "Step 8.2: Running deployment..."
    bash "$OPENSTACK_SCRIPT" deploy

    log_info "Step 8.3: Running post-deploy..."
    bash "$OPENSTACK_SCRIPT" post-deploy

    log_success "OpenStack deployment complete"
}

# =============================================================================
# PHASE 9: Verification
# =============================================================================
phase9_verify() {
    log_section "PHASE 9: Verification"

    log_info "Running verification tests..."
    bash "$OPENSTACK_SCRIPT" verify

    log_success "Verification complete!"
}

# =============================================================================
# Main Execution
# =============================================================================
main() {
    log_section "Starting Complete OpenStack + Ceph Deployment"
    log_info "This will take approximately 30-45 minutes"
    echo ""

    phase1_openstack_prereqs
    phase2_create_base_configs
    phase3_openstack_bootstrap
    phase4_install_ceph
    phase5_install_ceph_client
    phase6_create_ceph_users
    phase7_distribute_ceph_configs
    phase8_openstack_deploy
    phase9_verify

    log_section "DEPLOYMENT COMPLETE!"
    log_success "OpenStack with Ceph backend is now fully operational"
    echo ""
    log_info "Access Horizon dashboard at: http://10.100.0.254"
    log_info "Load OpenStack credentials: source /etc/kolla/admin-openrc.sh"
    echo ""
}

# Handle script arguments
case "${1:-all}" in
    phase1)
        phase1_openstack_prereqs
        ;;
    phase2)
        phase2_create_base_configs
        ;;
    phase3)
        phase3_openstack_bootstrap
        ;;
    phase4)
        phase4_install_ceph
        ;;
    phase5)
        phase5_install_ceph_client
        ;;
    phase6)
        phase6_create_ceph_users
        ;;
    phase7)
        phase7_distribute_ceph_configs
        ;;
    phase8)
        phase8_openstack_deploy
        ;;
    phase9)
        phase9_verify
        ;;
    *)
        main
        ;;
esac