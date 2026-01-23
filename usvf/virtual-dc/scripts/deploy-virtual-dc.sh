#!/bin/bash
################################################################################
# Virtual DC Deployment Script
# 
# This script orchestrates the deployment of a complete virtual datacenter
# including hypervisors, SONiC switches, BGP configuration, and networking
#
# Usage: ./deploy-virtual-dc.sh [options]
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MODULES_DIR="$PROJECT_ROOT/modules"
CONFIG_DIR="$PROJECT_ROOT/config"
TEMPLATES_DIR="$PROJECT_ROOT/templates"

# Default configuration file
CONFIG_FILE="${CONFIG_FILE:-$CONFIG_DIR/topology.yaml}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Banner
print_banner() {
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║           Virtual Datacenter Deployment System                ║
║                                                               ║
║  Automated deployment of hypervisors, SONiC switches,        ║
║  and BGP unnumbered routing infrastructure                    ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
}

# Show usage
usage() {
    cat << EOF
Usage: $0 [options]

Options:
    -c, --config FILE       Configuration file (default: config/topology.yaml)
    -v, --validate          Validate configuration only (no deployment)
    -d, --dry-run          Show what would be deployed without making changes
    -s, --step STEP        Deploy specific step only
    
    --check-prereqs        Check prerequisites and download Ubuntu 24.04 image
    --destroy              Destroy all Virtual DC resources
    --destroy-force        Destroy without confirmation prompt
    --keep-base-images     Keep base Ubuntu images when destroying
    --stop                 Stop all VMs (graceful shutdown)
    --start                Start all VMs
    --list                 List all Virtual DC resources
    
    -h, --help             Show this help message

Steps:
    validate    - Validate the configuration file
    prereqs     - Check and install prerequisites
    network     - Create management network
    hypervisors - Deploy hypervisor VMs
    switches    - Deploy SONiC switch VMs
    cabling     - Configure virtual cabling
    wait-ssh    - Wait for all VMs to be SSH-accessible
    verify      - Verify the deployment
    all         - Run all steps (default)

Examples:
    # Full deployment with default config
    $0

    # Check prerequisites and download Ubuntu 24.04
    $0 --check-prereqs

    # Validate configuration only
    $0 --validate

    # Deploy specific step
    $0 --step hypervisors

    # Use custom configuration
    $0 --config my-topology.yaml

    # List all resources
    $0 --list

    # Stop all VMs
    $0 --stop

    # Start all VMs
    $0 --start

    # Destroy everything (with confirmation)
    $0 --destroy

    # Destroy everything (no confirmation, keep base images)
    $0 --destroy-force --keep-base-images

EOF
    exit 1
}

# Parse command line arguments
VALIDATE_ONLY=false
DRY_RUN=false
STEP="all"
ACTION=""
FORCE_DESTROY=false
KEEP_BASE_IMAGES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -v|--validate)
            VALIDATE_ONLY=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -s|--step)
            STEP="$2"
            shift 2
            ;;
        --check-prereqs)
            ACTION="check-prereqs"
            shift
            ;;
        --destroy)
            ACTION="destroy"
            shift
            ;;
        --destroy-force)
            ACTION="destroy"
            FORCE_DESTROY=true
            shift
            ;;
        --keep-base-images)
            KEEP_BASE_IMAGES=true
            shift
            ;;
        --stop)
            ACTION="stop"
            shift
            ;;
        --start)
            ACTION="start"
            shift
            ;;
        --list)
            ACTION="list"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Handle special actions first
if [[ -n "$ACTION" ]]; then
    print_banner
    
    case "$ACTION" in
        check-prereqs)
            log_info "Checking prerequisites and downloading Ubuntu 24.04..."
            echo
            # Source modules first
            for module in "$MODULES_DIR"/*.sh; do
                if [[ -f "$module" ]]; then
                    source "$module"
                fi
            done
            check_prerequisites
            log_success "Prerequisites check complete!"
            log_info ""
            log_info "Ubuntu 24.04 cloud image location:"
            log_info "  $PROJECT_ROOT/images/ubuntu-24.04-server-cloudimg-amd64.img"
            exit 0
            ;;
        destroy)
            log_info "Destroying Virtual DC resources..."
            echo
            for module in "$MODULES_DIR"/*.sh; do
                if [[ -f "$module" ]]; then
                    source "$module"
                fi
            done
            destroy_virtual_dc "$CONFIG_FILE" "$FORCE_DESTROY" "$KEEP_BASE_IMAGES"
            exit 0
            ;;
        stop)
            log_info "Stopping all VMs..."
            echo
            for module in "$MODULES_DIR"/*.sh; do
                if [[ -f "$module" ]]; then
                    source "$module"
                fi
            done
            stop_all_vms "$CONFIG_FILE"
            log_success "All VMs stopped"
            exit 0
            ;;
        start)
            log_info "Starting all VMs..."
            echo
            for module in "$MODULES_DIR"/*.sh; do
                if [[ -f "$module" ]]; then
                    source "$module"
                fi
            done
            start_all_vms "$CONFIG_FILE"
            log_success "All VMs started"
            exit 0
            ;;
        list)
            for module in "$MODULES_DIR"/*.sh; do
                if [[ -f "$module" ]]; then
                    source "$module"
                fi
            done
            list_resources "$CONFIG_FILE"
            exit 0
            ;;
    esac
fi

print_banner
log_info "Configuration file: $CONFIG_FILE"
log_info "Deployment mode: ${DRY_RUN:+DRY RUN }${VALIDATE_ONLY:+VALIDATE ONLY }${STEP}"
echo

# Source all module scripts
log_info "Loading modules..."
for module in "$MODULES_DIR"/*.sh; do
    if [[ -f "$module" ]]; then
        source "$module"
        log_info "Loaded: $(basename "$module")"
    fi
done
echo

# Wait for all VMs to be SSH accessible
wait_for_all_vms() {
    local config_file="$1"

    log_info "Waiting for all VMs to be SSH-accessible (cloud-init in progress)..."

    # Get datacenter name
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")

    # Get SSH key path using VDC helper function
    local ssh_key_path=$(get_vdc_ssh_private_key "$dc_name")
    if [[ ! -f "$ssh_key_path" ]]; then
        log_warn "SSH key not found at $ssh_key_path, skipping SSH check"
        return 0
    fi

    local all_ready=true

    # Wait for hypervisors - read IP from topology
    local hv_count=$(yq eval '.hypervisors | length' "$config_file")
    for i in $(seq 0 $((hv_count - 1))); do
        local hv_name=$(yq eval ".hypervisors[$i].name" "$config_file")
        local vm_name="${dc_name}-${hv_name}"
        local mgmt_ip=$(yq eval ".hypervisors[$i].management.ip" "$config_file" | cut -d'/' -f1)

        if [[ -z "$mgmt_ip" || "$mgmt_ip" == "null" ]]; then
            log_warn "No management IP configured for $vm_name, skipping"
            continue
        fi

        log_info "Checking $vm_name at $mgmt_ip..."
        if ! wait_for_vm "$mgmt_ip" "$ssh_key_path"; then
            log_warn "Failed to connect to $vm_name at $mgmt_ip"
            all_ready=false
        fi
    done

    # Wait for leaf switches - read IP from topology
    local leaf_count=$(yq eval '.switches.leaf | length' "$config_file")
    for i in $(seq 0 $((leaf_count - 1))); do
        local leaf_name=$(yq eval ".switches.leaf[$i].name" "$config_file")
        local vm_name="${dc_name}-${leaf_name}"
        local mgmt_ip=$(yq eval ".switches.leaf[$i].management.ip" "$config_file" | cut -d'/' -f1)

        if [[ -z "$mgmt_ip" || "$mgmt_ip" == "null" ]]; then
            log_warn "No management IP configured for $vm_name, skipping"
            continue
        fi

        log_info "Checking $vm_name at $mgmt_ip..."
        if ! wait_for_vm "$mgmt_ip" "$ssh_key_path"; then
            log_warn "Failed to connect to $vm_name at $mgmt_ip"
            all_ready=false
        fi
    done

    # Wait for spine switches - read IP from topology
    local spine_count=$(yq eval '.switches.spine | length' "$config_file")
    for i in $(seq 0 $((spine_count - 1))); do
        local spine_name=$(yq eval ".switches.spine[$i].name" "$config_file")
        local vm_name="${dc_name}-${spine_name}"
        local mgmt_ip=$(yq eval ".switches.spine[$i].management.ip" "$config_file" | cut -d'/' -f1)

        if [[ -z "$mgmt_ip" || "$mgmt_ip" == "null" ]]; then
            log_warn "No management IP configured for $vm_name, skipping"
            continue
        fi

        log_info "Checking $vm_name at $mgmt_ip..."
        if ! wait_for_vm "$mgmt_ip" "$ssh_key_path"; then
            log_warn "Failed to connect to $vm_name at $mgmt_ip"
            all_ready=false
        fi
    done

    # Wait for superspine switches - read IP from topology
    local superspine_count=$(yq eval '.switches.superspine | length' "$config_file")
    for i in $(seq 0 $((superspine_count - 1))); do
        local superspine_name=$(yq eval ".switches.superspine[$i].name" "$config_file")
        local vm_name="${dc_name}-${superspine_name}"
        local mgmt_ip=$(yq eval ".switches.superspine[$i].management.ip" "$config_file" | cut -d'/' -f1)

        if [[ -z "$mgmt_ip" || "$mgmt_ip" == "null" ]]; then
            log_warn "No management IP configured for $vm_name, skipping"
            continue
        fi

        log_info "Checking $vm_name at $mgmt_ip..."
        if ! wait_for_vm "$mgmt_ip" "$ssh_key_path"; then
            log_warn "Failed to connect to $vm_name at $mgmt_ip"
            all_ready=false
        fi
    done

    if [[ "$all_ready" == "true" ]]; then
        log_success "All VMs are SSH-accessible and ready!"
        return 0
    else
        log_warn "Some VMs were not reachable within timeout"
        return 1
    fi
}

# Main deployment flow
main() {
    local steps_to_run=()
    
    if [[ "$STEP" == "all" ]]; then
        steps_to_run=(validate prereqs network p2p-networks hypervisors switches cabling wait-ssh verify)
    else
        steps_to_run=("$STEP")
    fi
    
    log_info "Starting Virtual DC deployment..."
    echo
    
    for step in "${steps_to_run[@]}"; do
        case "$step" in
            validate)
                log_info "═══ Step 1: Validating Configuration ═══"
                validate_configuration "$CONFIG_FILE"
                log_success "Configuration validation complete"
                ;;
            prereqs)
                if [[ "$VALIDATE_ONLY" == "true" ]]; then
                    continue
                fi
                log_info "═══ Step 2: Checking Prerequisites ═══"
                check_prerequisites
                log_success "Prerequisites check complete"
                ;;
            network)
                if [[ "$VALIDATE_ONLY" == "true" ]]; then
                    continue
                fi
                log_info "═══ Step 3: Creating Management Network ═══"
                create_management_network "$CONFIG_FILE" "$DRY_RUN"
                log_success "Management network created"
                ;;
            p2p-networks)
                if [[ "$VALIDATE_ONLY" == "true" ]]; then
                    continue
                fi
                log_info "═══ Step 4: Pre-Creating P2P Networks ═══"
                create_p2p_networks "$CONFIG_FILE" "$DRY_RUN"
                log_success "All P2P networks pre-created"
                ;;
            hypervisors)
                if [[ "$VALIDATE_ONLY" == "true" ]]; then
                    continue
                fi
                log_info "═══ Step 5: Deploying Hypervisors ═══"
                deploy_hypervisors "$CONFIG_FILE" "$DRY_RUN"
                log_success "Hypervisors deployed (directly connected to P2P networks)"
                ;;
            switches)
                if [[ "$VALIDATE_ONLY" == "true" ]]; then
                    continue
                fi
                log_info "═══ Step 6: Deploying SONiC Switches ═══"
                deploy_switches "$CONFIG_FILE" "$DRY_RUN"
                log_success "Switches deployed (directly connected to P2P networks)"
                ;;
            cabling)
                if [[ "$VALIDATE_ONLY" == "true" ]]; then
                    continue
                fi
                log_info "═══ Step 7: Verifying Virtual Cabling ═══"
                configure_cabling "$CONFIG_FILE" "$DRY_RUN"
                log_success "Cabling verified"
                ;;
            wait-ssh)
                if [[ "$VALIDATE_ONLY" == "true" ]]; then
                    continue
                fi
                log_info "═══ Step 8: Waiting for VMs to be SSH-Accessible ═══"
                wait_for_all_vms "$CONFIG_FILE"
                log_success "All VMs are SSH-accessible and ready"
                ;;
            verify)
                if [[ "$VALIDATE_ONLY" == "true" ]]; then
                    continue
                fi
                log_info "═══ Step 9: Verifying Deployment ═══"
                verify_deployment "$CONFIG_FILE"
                log_success "Deployment verification complete"
                ;;
            *)
                log_error "Unknown step: $step"
                exit 1
                ;;
        esac
        echo
    done
    
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        log_success "Configuration validation completed successfully!"
    else
        log_success "Virtual DC deployment completed successfully!"
        echo
        log_info "Next steps:"
        log_info "  1. Check VM status: virsh list --all"
        log_info "  2. Access hypervisors via SSH (IPs are auto-assigned, check with: virsh domifaddr <vm-name>)"
        log_info "  3. Verify BGP (already configured via cloud-init): ssh ubuntu@<vm-ip> 'vtysh -c \"show bgp summary\"'"
        log_info "  4. View network topology: ./scripts/show-topology.sh"
    fi
}

# Trap errors
trap 'log_error "Deployment failed at line $LINENO. Check logs for details."' ERR

# Run main
main

exit 0
