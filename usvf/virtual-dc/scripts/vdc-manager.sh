#!/bin/bash
################################################################################
# VDC Manager - Virtual Datacenter Manager
#
# Manages multiple isolated virtual datacenters with namespace isolation
#
# Commands:
#   list              - List all virtual datacenters
#   create            - Create a new virtual datacenter
#   destroy           - Destroy a virtual datacenter
#   status            - Show status of a virtual datacenter
#   resources         - List detailed resources in a VDC
#   topology          - Display topology of a VDC
#   cleanup-orphans   - Find and cleanup orphaned resources in a VDC
#
# Usage:
#   ./vdc-manager.sh list
#   ./vdc-manager.sh create --name prod --config topology.yaml
#   ./vdc-manager.sh destroy --name prod
#   ./vdc-manager.sh status --name prod
#   ./vdc-manager.sh resources --name prod
#   ./vdc-manager.sh topology --name prod
#   ./vdc-manager.sh cleanup-orphans --name prod
################################################################################

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source required modules
source "$PROJECT_ROOT/modules/vdc-paths.sh"
source "$PROJECT_ROOT/modules/vdc.sh"
source "$PROJECT_ROOT/modules/namespace.sh"

# VDC Registry file
VDC_REGISTRY="$PROJECT_ROOT/config/vdc-registry.json"

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $*"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $*"
}

log_warn() {
    echo -e "\033[0;33m[WARN]\033[0m $*"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $*"
}

################################################################################
# Registry Management
################################################################################

init_registry() {
    if [[ ! -f "$VDC_REGISTRY" ]]; then
        log_info "Initializing VDC registry..."
        mkdir -p "$(dirname "$VDC_REGISTRY")"
        cat > "$VDC_REGISTRY" <<EOF
{
  "version": "1.0",
  "virtual_datacenters": []
}
EOF
        log_success "Registry initialized at $VDC_REGISTRY"
    fi
}

get_vdc_list() {
    init_registry
    jq -r '.virtual_datacenters[].name' "$VDC_REGISTRY" 2>/dev/null || echo ""
}

get_vdc_info() {
    local vdc_name="$1"
    init_registry
    jq -r ".virtual_datacenters[] | select(.name == \"$vdc_name\")" "$VDC_REGISTRY"
}

vdc_exists() {
    local vdc_name="$1"
    local info=$(get_vdc_info "$vdc_name")
    [[ -n "$info" ]]
}

add_vdc_to_registry() {
    local vdc_name="$1"
    local namespace="$2"
    local config_file="$3"
    local mgmt_subnet="$4"
    
    init_registry
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local new_vdc=$(cat <<EOF
{
  "name": "$vdc_name",
  "namespace": "$namespace",
  "created_at": "$timestamp",
  "status": "created",
  "management_subnet": "$mgmt_subnet",
  "config_file": "$config_file",
  "vms": [],
  "networks": [],
  "switches": []
}
EOF
)
    
    # Add to registry
    jq ".virtual_datacenters += [$new_vdc]" "$VDC_REGISTRY" > "${VDC_REGISTRY}.tmp"
    mv "${VDC_REGISTRY}.tmp" "$VDC_REGISTRY"
    
    log_success "Added VDC '$vdc_name' to registry"
}

remove_vdc_from_registry() {
    local vdc_name="$1"
    
    init_registry
    jq ".virtual_datacenters |= map(select(.name != \"$vdc_name\"))" "$VDC_REGISTRY" > "${VDC_REGISTRY}.tmp"
    mv "${VDC_REGISTRY}.tmp" "$VDC_REGISTRY"
    
    log_success "Removed VDC '$vdc_name' from registry"
}

update_vdc_status() {
    local vdc_name="$1"
    local status="$2"
    
    init_registry
    jq "(.virtual_datacenters[] | select(.name == \"$vdc_name\") | .status) = \"$status\"" \
        "$VDC_REGISTRY" > "${VDC_REGISTRY}.tmp"
    mv "${VDC_REGISTRY}.tmp" "$VDC_REGISTRY"
}

################################################################################
# Command: List VDCs
################################################################################

cmd_list() {
    log_info "═══════════════════════════════════════════════════════════"
    log_info "              VIRTUAL DATACENTERS"
    log_info "═══════════════════════════════════════════════════════════"
    echo ""
    
    init_registry
    
    local vdc_count=$(jq -r '.virtual_datacenters | length' "$VDC_REGISTRY")
    
    if [[ $vdc_count -eq 0 ]]; then
        log_warn "No virtual datacenters found"
        echo ""
        log_info "Create a VDC with: ./vdc-manager.sh create --name <name> --config <file>"
        return 0
    fi
    
    printf "%-20s %-20s %-25s %-15s %-20s\n" "NAME" "NAMESPACE" "CREATED" "STATUS" "MANAGEMENT SUBNET"
    printf "%-20s %-20s %-25s %-15s %-20s\n" "----" "---------" "-------" "------" "-----------------"
    
    jq -r '.virtual_datacenters[] | 
        [.name, .namespace, .created_at, .status, .management_subnet] | 
        @tsv' "$VDC_REGISTRY" | \
    while IFS=$'\t' read -r name namespace created status subnet; do
        # Get actual status
        local actual_status=$(get_vdc_actual_status "$name")
        printf "%-20s %-20s %-25s %-15s %-20s\n" "$name" "$namespace" "$created" "$actual_status" "$subnet"
    done
    
    echo ""
    log_info "Total VDCs: $vdc_count"
    echo ""
}

get_vdc_actual_status() {
    local vdc_name="$1"
    
    # Check if namespace exists
    local namespace="vdc-${vdc_name}"
    if ! ip netns list 2>/dev/null | grep -q "^${namespace}"; then
        echo "stopped"
        return
    fi
    
    # Check if any VMs are running
    local running_vms=$(virsh list --name 2>/dev/null | grep -c "^${vdc_name}-" || echo "0")
    if [[ $running_vms -gt 0 ]]; then
        echo "running"
    else
        echo "stopped"
    fi
}

################################################################################
# Command: Create VDC
################################################################################

cmd_create() {
    local vdc_name=""
    local config_file=""
    local mgmt_subnet=""
    local auto_subnet=true
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                vdc_name="$2"
                shift 2
                ;;
            --config)
                config_file="$2"
                shift 2
                ;;
            --subnet)
                mgmt_subnet="$2"
                auto_subnet=false
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$vdc_name" ]]; then
        log_error "VDC name is required. Use: --name <name>"
        exit 1
    fi
    
    if [[ -z "$config_file" ]]; then
        log_error "Config file is required. Use: --config <file>"
        exit 1
    fi
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Config file not found: $config_file"
        exit 1
    fi
    
    # Check if VDC already exists
    if vdc_exists "$vdc_name"; then
        log_error "VDC '$vdc_name' already exists"
        exit 1
    fi
    
    # Auto-assign subnet if not provided
    if [[ "$auto_subnet" == "true" ]]; then
        mgmt_subnet=$(assign_next_subnet)
        log_info "Auto-assigned management subnet: $mgmt_subnet"
    fi
    
    log_info "═══════════════════════════════════════════════════════════"
    log_info "         CREATING VIRTUAL DATACENTER: $vdc_name"
    log_info "═══════════════════════════════════════════════════════════"
    echo ""
    log_info "Name: $vdc_name"
    log_info "Config: $config_file"
    log_info "Management Subnet: $mgmt_subnet"
    echo ""
    
    # Create namespace
    local namespace="vdc-${vdc_name}"
    log_info "Step 1/5: Creating network namespace..."
    create_vdc_namespace "$namespace"
    
    # Add to registry
    log_info "Step 2/5: Registering VDC..."
    add_vdc_to_registry "$vdc_name" "$namespace" "$config_file" "$mgmt_subnet"
    
    # Copy config to VDC directory
    log_info "Step 3/5: Setting up VDC configuration..."
    local vdc_config_dir="$PROJECT_ROOT/config/vdc-${vdc_name}"
    mkdir -p "$vdc_config_dir"
    cp "$config_file" "$vdc_config_dir/topology.yaml"
    
    # Update config with VDC-specific settings
    update_vdc_config "$vdc_config_dir/topology.yaml" "$vdc_name" "$mgmt_subnet"
    
    # Deploy VDC
    log_info "Step 4/5: Deploying virtual datacenter..."
    deploy_vdc "$vdc_name" "$vdc_config_dir/topology.yaml"
    
    # Update status
    log_info "Step 5/5: Finalizing..."
    update_vdc_status "$vdc_name" "running"
    
    echo ""
    log_success "═══════════════════════════════════════════════════════════"
    log_success "  Virtual Datacenter '$vdc_name' created successfully!"
    log_success "═══════════════════════════════════════════════════════════"
    echo ""
    log_info "Access your VDC:"
    log_info "  - View status: ./vdc-manager.sh status --name $vdc_name"
    log_info "  - View resources: ./vdc-manager.sh resources --name $vdc_name"
    log_info "  - View topology: ./vdc-manager.sh topology --name $vdc_name"
    echo ""
}

assign_next_subnet() {
    # Find next available /24 subnet in 192.168.x.0/24 range
    local base_octet=10
    
    init_registry
    local used_subnets=$(jq -r '.virtual_datacenters[].management_subnet' "$VDC_REGISTRY" | cut -d'.' -f3)
    
    while true; do
        local subnet="192.168.${base_octet}.0/24"
        if ! echo "$used_subnets" | grep -q "^${base_octet}$"; then
            echo "$subnet"
            return
        fi
        base_octet=$((base_octet + 1))
        if [[ $base_octet -gt 254 ]]; then
            log_error "No available subnets in 192.168.x.0/24 range"
            exit 1
        fi
    done
}

update_vdc_config() {
    local config_file="$1"
    local vdc_name="$2"
    local mgmt_subnet="$3"

    # Update datacenter_name
    yq eval ".global.datacenter_name = \"${vdc_name}\"" -i "$config_file"

    # Extract network portion: 192.168.10.0/24 -> 192.168.10
    local subnet_ip=$(echo "$mgmt_subnet" | cut -d'/' -f1)
    local network_base=$(echo "$subnet_ip" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+$/\1/')
    local gateway="${network_base}.1"

    log_info "Updating management IPs for all devices to match subnet ${mgmt_subnet}..."

    # Assign continuous IPs starting from .11 (reserving .1-.10 for gateway and DHCP)
    local next_ip=11

    # Update hypervisor management IPs
    local hv_count=$(yq eval '.hypervisors | length' "$config_file")
    for i in $(seq 0 $((hv_count - 1))); do
        local new_ip="${network_base}.${next_ip}/24"
        yq eval ".hypervisors[$i].management.ip = \"${new_ip}\"" -i "$config_file"
        next_ip=$((next_ip + 1))
    done
    local hv_end_ip=$((next_ip - 1))

    # Update leaf switch management IPs
    local leaf_count=$(yq eval '.switches.leaf | length' "$config_file")
    local leaf_start_ip=$next_ip
    for i in $(seq 0 $((leaf_count - 1))); do
        local new_ip="${network_base}.${next_ip}/24"
        yq eval ".switches.leaf[$i].management.ip = \"${new_ip}\"" -i "$config_file"
        next_ip=$((next_ip + 1))
    done
    local leaf_end_ip=$((next_ip - 1))

    # Update spine switch management IPs
    local spine_count=$(yq eval '.switches.spine | length' "$config_file")
    local spine_start_ip=$next_ip
    for i in $(seq 0 $((spine_count - 1))); do
        local new_ip="${network_base}.${next_ip}/24"
        yq eval ".switches.spine[$i].management.ip = \"${new_ip}\"" -i "$config_file"
        next_ip=$((next_ip + 1))
    done
    local spine_end_ip=$((next_ip - 1))

    # Update superspine switch management IPs
    local superspine_count=$(yq eval '.switches.superspine | length' "$config_file")
    local superspine_start_ip=$next_ip
    for i in $(seq 0 $((superspine_count - 1))); do
        local new_ip="${network_base}.${next_ip}/24"
        yq eval ".switches.superspine[$i].management.ip = \"${new_ip}\"" -i "$config_file"
        next_ip=$((next_ip + 1))
    done
    local superspine_end_ip=$((next_ip - 1))

    log_success "Updated VDC configuration with continuous IP allocation:"
    log_success "  - Gateway: $gateway"
    log_success "  - Reserved for infrastructure: ${network_base}.2-10"
    if [[ $hv_count -gt 0 ]]; then
        log_success "  - Hypervisors (${hv_count}): ${network_base}.11-${hv_end_ip}"
    fi
    if [[ $leaf_count -gt 0 ]]; then
        log_success "  - Leaf switches (${leaf_count}): ${network_base}.${leaf_start_ip}-${leaf_end_ip}"
    fi
    if [[ $spine_count -gt 0 ]]; then
        log_success "  - Spine switches (${spine_count}): ${network_base}.${spine_start_ip}-${spine_end_ip}"
    fi
    if [[ $superspine_count -gt 0 ]]; then
        log_success "  - SuperSpine switches (${superspine_count}): ${network_base}.${superspine_start_ip}-${superspine_end_ip}"
    fi
}

################################################################################
# Command: Destroy VDC
################################################################################

cmd_destroy() {
    local vdc_name=""
    local force=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                vdc_name="$2"
                shift 2
                ;;
            --force)
                force=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Validate
    if [[ -z "$vdc_name" ]]; then
        log_error "VDC name is required. Use: --name <name>"
        exit 1
    fi
    
    if ! vdc_exists "$vdc_name"; then
        log_error "VDC '$vdc_name' does not exist"
        exit 1
    fi
    
    # Confirm destruction
    if [[ "$force" != "true" ]]; then
        echo ""
        log_warn "═══════════════════════════════════════════════════════════"
        log_warn "  WARNING: This will destroy Virtual Datacenter '$vdc_name'"
        log_warn "═══════════════════════════════════════════════════════════"
        echo ""
        read -p "Are you sure you want to proceed? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Destruction cancelled"
            exit 0
        fi
    fi
    
    log_info "═══════════════════════════════════════════════════════════"
    log_info "       DESTROYING VIRTUAL DATACENTER: $vdc_name"
    log_info "═══════════════════════════════════════════════════════════"
    echo ""
    
    # Destroy VDC resources
    log_info "Step 1/4: Destroying VDC resources..."
    destroy_vdc "$vdc_name"
    
    # Destroy namespace
    log_info "Step 2/4: Removing network namespace..."
    local namespace="vdc-${vdc_name}"
    destroy_vdc_namespace "$namespace"
    
    # Remove VDC directory (includes all disks, cloud-init, bgp configs, network XMLs, ssh keys)
    log_info "Step 3/4: Cleaning up VDC directory..."
    cleanup_vdc_directory "$vdc_name"
    
    # Remove from registry
    log_info "Step 4/4: Unregistering VDC..."
    remove_vdc_from_registry "$vdc_name"
    
    echo ""
    log_success "═══════════════════════════════════════════════════════════"
    log_success "  Virtual Datacenter '$vdc_name' destroyed successfully!"
    log_success "═══════════════════════════════════════════════════════════"
    echo ""
}

################################################################################
# Command: Status
################################################################################

cmd_status() {
    local vdc_name=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                vdc_name="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$vdc_name" ]]; then
        log_error "VDC name is required. Use: --name <name>"
        exit 1
    fi
    
    if ! vdc_exists "$vdc_name"; then
        log_error "VDC '$vdc_name' does not exist"
        exit 1
    fi
    
    show_vdc_status "$vdc_name"
}

################################################################################
# Command: Resources
################################################################################

cmd_resources() {
    local vdc_name=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                vdc_name="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$vdc_name" ]]; then
        log_error "VDC name is required. Use: --name <name>"
        exit 1
    fi
    
    if ! vdc_exists "$vdc_name"; then
        log_error "VDC '$vdc_name' does not exist"
        exit 1
    fi
    
    show_vdc_resources "$vdc_name"
}

################################################################################
# Command: Topology
################################################################################

cmd_topology() {
    local vdc_name=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                vdc_name="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$vdc_name" ]]; then
        log_error "VDC name is required. Use: --name <name>"
        exit 1
    fi
    
    if ! vdc_exists "$vdc_name"; then
        log_error "VDC '$vdc_name' does not exist"
        exit 1
    fi
    
    show_vdc_topology "$vdc_name"
}

################################################################################
# Command: Cleanup Orphans
################################################################################

cmd_cleanup_orphans() {
    local vdc_name=""
    local force=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                vdc_name="$2"
                shift 2
                ;;
            --force)
                force=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$vdc_name" ]]; then
        log_error "VDC name is required. Use: --name <name>"
        exit 1
    fi
    
    if ! vdc_exists "$vdc_name"; then
        log_error "VDC '$vdc_name' does not exist"
        exit 1
    fi
    
    cleanup_orphaned_resources "$vdc_name" "$force"
}

################################################################################
# Help
################################################################################

show_help() {
    cat <<EOF
VDC Manager - Virtual Datacenter Manager

Usage: $(basename "$0") <command> [options]

Commands:
  list                          List all virtual datacenters
  create                        Create a new virtual datacenter
  destroy                       Destroy a virtual datacenter
  status                        Show status of a virtual datacenter
  resources                     List detailed resources in a VDC
  topology                      Display topology of a VDC
  cleanup-orphans               Find and cleanup orphaned resources

Options:
  --name <name>                 Name of the virtual datacenter
  --config <file>               Path to topology configuration file
  --subnet <subnet>             Management subnet (default: auto-assigned)
  --force                       Force operation without confirmation

Examples:
  # List all VDCs
  $(basename "$0") list

  # Create a new VDC
  $(basename "$0") create --name prod --config config/topology.yaml

  # Create VDC with custom subnet
  $(basename "$0") create --name staging --config topology.yaml --subnet 192.168.20.0/24

  # Show VDC status
  $(basename "$0") status --name prod

  # Show VDC resources
  $(basename "$0") resources --name prod

  # Show VDC topology
  $(basename "$0") topology --name prod

  # Cleanup orphaned resources
  $(basename "$0") cleanup-orphans --name prod

  # Destroy a VDC
  $(basename "$0") destroy --name prod

  # Force destroy without confirmation
  $(basename "$0") destroy --name prod --force

EOF
}

################################################################################
# Main
################################################################################

main() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        list)
            cmd_list "$@"
            ;;
        create)
            cmd_create "$@"
            ;;
        destroy)
            cmd_destroy "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        resources)
            cmd_resources "$@"
            ;;
        topology)
            cmd_topology "$@"
            ;;
        cleanup-orphans)
            cmd_cleanup_orphans "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
