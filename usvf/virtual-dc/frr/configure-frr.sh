#!/bin/bash
################################################################################
# FRR Configuration Tool
#
# Standalone script to configure FRR on remote devices via SSH.
# Can work with explicit device configs or auto-discover from VDC topology.
#
# Usage:
#   ./configure-frr.sh -c <config.yaml> [options]
#   ./configure-frr.sh --vdc-config <topology.yaml> [options]
#
# Options:
#   -c, --config FILE       FRR device configuration file
#   --vdc-config FILE       Use VDC topology for device and neighbor discovery
#   -d, --device NAME       Configure specific device only
#   --dry-run               Preview generated configs without deploying
#   --prepare               Install FRR first (calls prepare-frr.sh)
#   --ssh-key PATH          SSH private key for authentication
#   --ssh-password PASS     SSH password for authentication (requires sshpass)
#   --ssh-user USER         SSH username (default: ubuntu)
#   -h, --help              Show this help message
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source functions library
source "$SCRIPT_DIR/frr-functions.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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

log_config() {
    echo -e "${CYAN}$*${NC}"
}

# Print banner
print_banner() {
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║              FRR Configuration Tool                           ║
║                                                               ║
║  Configure FRRouting on remote devices via SSH               ║
║  Supports standalone mode and VDC integration                ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
}

# Show usage
usage() {
    cat << EOF
Usage: $0 [options]

Options:
    -c, --config FILE       FRR device configuration file (YAML)
    --vdc-config FILE       Use VDC topology for device and neighbor discovery
    -d, --device NAME       Configure specific device only (can be repeated)
    --dry-run               Preview generated configs without deploying
    --prepare               Install FRR on devices first (calls prepare-frr.sh)
    --ssh-key PATH          SSH private key path (overrides config file)
    --ssh-password PASS     SSH password (overrides config file, requires sshpass)
    --ssh-user USER         SSH username (default: ubuntu)
    --verify-only           Only verify FRR status, don't deploy
    -v, --verbose           Verbose output
    -h, --help              Show this help message

Configuration Modes:

  1. Standalone Mode (-c config.yaml):
     Use explicit device configuration file with host IPs and neighbors.

  2. VDC Integration Mode (--vdc-config topology.yaml):
     Auto-discover devices and neighbors from VDC topology.
     Uses VDC SSH keys from config/vdc-{dc}/ssh-keys/

Examples:
    # Configure all devices from config file
    $0 -c frr/examples/standalone-device.yaml

    # Dry-run to preview configs
    $0 -c frr/examples/standalone-device.yaml --dry-run

    # Configure specific device with custom SSH key
    $0 -c config.yaml -d switch-1 --ssh-key ~/.ssh/id_rsa

    # Use VDC topology for auto-discovery
    $0 --vdc-config config/topology.yaml --dry-run

    # Verify FRR status on VDC devices
    $0 --vdc-config config/topology.yaml --verify-only

EOF
    exit 1
}

# Parse command line arguments
CONFIG_FILE=""
VDC_CONFIG=""
DRY_RUN=false
VERIFY_ONLY=false
VERBOSE=false
PREPARE_FIRST=false
SSH_KEY=""
SSH_PASSWORD=""
SSH_USER="ubuntu"
declare -a TARGET_DEVICES=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --vdc-config)
            VDC_CONFIG="$2"
            shift 2
            ;;
        -d|--device)
            TARGET_DEVICES+=("$2")
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --prepare)
            PREPARE_FIRST=true
            shift
            ;;
        --verify-only)
            VERIFY_ONLY=true
            shift
            ;;
        --ssh-key)
            SSH_KEY="$2"
            shift 2
            ;;
        --ssh-password)
            SSH_PASSWORD="$2"
            shift 2
            ;;
        --ssh-user)
            SSH_USER="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
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

# Validate arguments
if [[ -z "$CONFIG_FILE" && -z "$VDC_CONFIG" ]]; then
    log_error "Either -c/--config or --vdc-config is required"
    usage
fi

if [[ -n "$CONFIG_FILE" && -n "$VDC_CONFIG" ]]; then
    log_error "Cannot use both -c/--config and --vdc-config simultaneously"
    exit 1
fi

# Check for required tools
check_prerequisites() {
    if ! command -v yq &>/dev/null; then
        log_error "yq is required but not installed"
        log_info "Install with: brew install yq (macOS) or snap install yq (Linux)"
        exit 1
    fi

    if [[ -n "$SSH_PASSWORD" ]] && ! command -v sshpass &>/dev/null; then
        log_error "sshpass is required for password authentication but not installed"
        log_info "Install with: brew install sshpass (macOS) or apt install sshpass (Linux)"
        exit 1
    fi
}

# Configure device from standalone config
configure_device_from_config() {
    local config_file="$1"
    local device_index="$2"

    # Validate device config
    if ! validate_frr_device_config "$config_file" "$device_index"; then
        log_error "Invalid device configuration at index $device_index"
        return 1
    fi

    # Extract device info
    local name=$(yq eval ".frr_config.devices[$device_index].name" "$config_file")
    local host=$(yq eval ".frr_config.devices[$device_index].host" "$config_file")
    local router_id=$(yq eval ".frr_config.devices[$device_index].router_id" "$config_file")
    local asn=$(yq eval ".frr_config.devices[$device_index].asn" "$config_file")

    # Check if this device is in target list (if specified)
    if [[ ${#TARGET_DEVICES[@]} -gt 0 ]]; then
        local found=false
        for target in "${TARGET_DEVICES[@]}"; do
            if [[ "$target" == "$name" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == "false" ]]; then
            return 0
        fi
    fi

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Configuring device: $name"
    log_info "  Host: $host"
    log_info "  Router ID: $router_id"
    log_info "  ASN: $asn"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Get SSH credentials
    local auth_type="key"
    local auth_credential=""

    if [[ -n "$SSH_KEY" ]]; then
        auth_credential="$SSH_KEY"
    elif [[ -n "$SSH_PASSWORD" ]]; then
        auth_type="password"
        auth_credential="$SSH_PASSWORD"
    else
        # Try to get from config
        local config_auth_type=$(yq eval ".frr_config.devices[$device_index].ssh_auth.type" "$config_file")
        if [[ "$config_auth_type" == "key" ]]; then
            auth_credential=$(yq eval ".frr_config.devices[$device_index].ssh_auth.key_path" "$config_file")
            auth_credential="${auth_credential/#\~/$HOME}"
        elif [[ "$config_auth_type" == "password" ]]; then
            auth_type="password"
            auth_credential=$(yq eval ".frr_config.devices[$device_index].ssh_auth.password" "$config_file")
        fi
    fi

    local ssh_user=$(yq eval ".frr_config.devices[$device_index].ssh_user // \"$SSH_USER\"" "$config_file")
    if [[ "$ssh_user" == "null" ]]; then
        ssh_user="$SSH_USER"
    fi

    # Get neighbors
    local neighbors=$(get_neighbors_from_config "$config_file" "$device_index")
    log_info "  Neighbors: $neighbors"

    # Get options (redistribute settings, etc.)
    local device_type=$(yq eval ".frr_config.devices[$device_index].type // \"switch\"" "$config_file")

    # Get redistribute_interfaces for route-map filtering (optional)
    local redistribute_interfaces=""
    local ri_raw=$(yq eval ".frr_config.devices[$device_index].redistribute_interfaces" "$config_file" 2>/dev/null)
    if [[ -n "$ri_raw" && "$ri_raw" != "null" ]]; then
        # Check if it's an array (contains newlines or starts with -)
        if echo "$ri_raw" | grep -q "^-"; then
            redistribute_interfaces=$(yq eval ".frr_config.devices[$device_index].redistribute_interfaces | join(\" \")" "$config_file")
        else
            redistribute_interfaces="$ri_raw"
        fi
        log_info "  Redistribute interfaces: $redistribute_interfaces"
    fi

    # Generate FRR configuration
    local frr_config
    if [[ "$device_type" == "hypervisor" ]]; then
        if [[ -n "$redistribute_interfaces" ]]; then
            frr_config=$(generate_frr_hypervisor_config "$name" "$router_id" "$asn" "$neighbors" "$redistribute_interfaces")
        else
            frr_config=$(generate_frr_hypervisor_config "$name" "$router_id" "$asn" "$neighbors")
        fi
    else
        frr_config=$(generate_frr_switch_config "$name" "$router_id" "$asn" "$neighbors")
    fi

    # Dry-run mode: just print the config
    if [[ "$DRY_RUN" == "true" ]]; then
        echo
        log_info "Generated FRR configuration for $name:"
        echo "─────────────────────────────────────────"
        log_config "$frr_config"
        echo "─────────────────────────────────────────"
        echo
        return 0
    fi

    # Verify-only mode
    if [[ "$VERIFY_ONLY" == "true" ]]; then
        ssh_verify_frr_status "$host" "$auth_credential" "$auth_type" "$ssh_user"
        return $?
    fi

    # Deploy configuration
    if [[ -z "$auth_credential" ]]; then
        log_error "No SSH credentials available for $name"
        return 1
    fi

    # Wait for SSH to be available
    if ! wait_for_ssh "$host" "$auth_credential" "$auth_type" 3 "$ssh_user"; then
        log_error "Cannot connect to $host via SSH"
        return 1
    fi

    # Deploy FRR configuration
    ssh_deploy_frr_config "$host" "$auth_credential" "$auth_type" "$frr_config" "$ssh_user"
}

# Configure devices from VDC topology
configure_from_vdc_topology() {
    local vdc_config="$1"

    # Validate VDC config
    if ! validate_vdc_config "$vdc_config"; then
        log_error "Invalid VDC configuration"
        return 1
    fi

    local dc_name=$(yq eval '.global.datacenter_name' "$vdc_config")
    log_info "Using VDC topology: $dc_name"

    # Get SSH key path
    local ssh_key_path
    if [[ -n "$SSH_KEY" ]]; then
        ssh_key_path="$SSH_KEY"
    else
        # Use VDC SSH keys
        ssh_key_path="$PROJECT_ROOT/config/vdc-${dc_name}/ssh-keys/id_rsa"
        if [[ ! -f "$ssh_key_path" ]]; then
            # Try legacy path
            ssh_key_path="$PROJECT_ROOT/config/${dc_name}-ssh-key"
        fi
    fi

    if [[ ! -f "$ssh_key_path" && -z "$SSH_PASSWORD" ]]; then
        log_error "SSH key not found: $ssh_key_path"
        log_info "Specify --ssh-key or --ssh-password"
        return 1
    fi

    local auth_type="key"
    local auth_credential="$ssh_key_path"
    if [[ -n "$SSH_PASSWORD" ]]; then
        auth_type="password"
        auth_credential="$SSH_PASSWORD"
    fi

    # Get list of all devices
    local devices=$(list_vdc_devices "$vdc_config")

    for device_name in $devices; do
        # Check if this device is in target list (if specified)
        if [[ ${#TARGET_DEVICES[@]} -gt 0 ]]; then
            local found=false
            for target in "${TARGET_DEVICES[@]}"; do
                if [[ "$target" == "$device_name" ]]; then
                    found=true
                    break
                fi
            done
            if [[ "$found" == "false" ]]; then
                continue
            fi
        fi

        # Get device info
        local device_info=$(get_vdc_device_info "$vdc_config" "$device_name")
        if [[ -z "$device_info" ]]; then
            log_warn "Could not find device info for $device_name"
            continue
        fi

        local router_id=$(echo "$device_info" | yq eval '.router_id' -)
        local asn=$(echo "$device_info" | yq eval '.asn' -)
        local mgmt_ip=$(echo "$device_info" | yq eval '.management.ip' - | cut -d'/' -f1)
        local device_type=$(echo "$device_info" | yq eval '.type' -)

        if [[ -z "$mgmt_ip" || "$mgmt_ip" == "null" ]]; then
            log_warn "No management IP for $device_name, skipping"
            continue
        fi

        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_info "Configuring device: $device_name"
        log_info "  Host: $mgmt_ip"
        log_info "  Router ID: $router_id"
        log_info "  ASN: $asn"
        log_info "  Type: $device_type"
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # Get neighbors from cabling
        local neighbors=$(get_neighbors_from_vdc_cabling "$vdc_config" "$device_name")
        log_info "  Neighbors: $neighbors"

        # Generate FRR configuration
        local frr_config
        if [[ "$device_type" == "hypervisor" ]]; then
            frr_config=$(generate_frr_hypervisor_config "$device_name" "$router_id" "$asn" "$neighbors")
        else
            frr_config=$(generate_frr_switch_config "$device_name" "$router_id" "$asn" "$neighbors")
        fi

        # Dry-run mode
        if [[ "$DRY_RUN" == "true" ]]; then
            echo
            log_info "Generated FRR configuration for $device_name:"
            echo "─────────────────────────────────────────"
            log_config "$frr_config"
            echo "─────────────────────────────────────────"
            echo
            continue
        fi

        # Verify-only mode
        if [[ "$VERIFY_ONLY" == "true" ]]; then
            ssh_verify_frr_status "$mgmt_ip" "$auth_credential" "$auth_type" "$SSH_USER"
            continue
        fi

        # Wait for SSH and deploy
        if ! wait_for_ssh "$mgmt_ip" "$auth_credential" "$auth_type" 3 "$SSH_USER"; then
            log_warn "Cannot connect to $device_name at $mgmt_ip, skipping"
            continue
        fi

        ssh_deploy_frr_config "$mgmt_ip" "$auth_credential" "$auth_type" "$frr_config" "$SSH_USER"
    done
}

# Main
main() {
    print_banner
    echo

    check_prerequisites

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No changes will be made"
        echo
    fi

    if [[ "$VERIFY_ONLY" == "true" ]]; then
        log_info "VERIFY ONLY MODE - Only checking FRR status"
        echo
    fi

    # Run prepare-frr.sh first if --prepare is specified
    if [[ "$PREPARE_FIRST" == "true" && "$DRY_RUN" != "true" && "$VERIFY_ONLY" != "true" ]]; then
        log_info "Installing FRR on devices first..."
        echo

        local prepare_script="$SCRIPT_DIR/prepare-frr.sh"
        if [[ ! -f "$prepare_script" ]]; then
            log_error "prepare-frr.sh not found: $prepare_script"
            exit 1
        fi

        # Build prepare-frr.sh command with same arguments
        local prepare_cmd=("$prepare_script")
        if [[ -n "$CONFIG_FILE" ]]; then
            prepare_cmd+=("-c" "$CONFIG_FILE")
        elif [[ -n "$VDC_CONFIG" ]]; then
            prepare_cmd+=("--vdc-config" "$VDC_CONFIG")
        fi
        if [[ -n "$SSH_KEY" ]]; then
            prepare_cmd+=("--ssh-key" "$SSH_KEY")
        fi
        if [[ -n "$SSH_PASSWORD" ]]; then
            prepare_cmd+=("--ssh-password" "$SSH_PASSWORD")
        fi
        if [[ "$SSH_USER" != "ubuntu" ]]; then
            prepare_cmd+=("--ssh-user" "$SSH_USER")
        fi
        for device in "${TARGET_DEVICES[@]}"; do
            prepare_cmd+=("-d" "$device")
        done

        if ! "${prepare_cmd[@]}"; then
            log_error "FRR installation failed"
            exit 1
        fi

        echo
        log_success "FRR installation complete, proceeding with configuration..."
        echo
    fi

    if [[ -n "$CONFIG_FILE" ]]; then
        # Standalone mode
        if [[ ! -f "$CONFIG_FILE" ]]; then
            log_error "Config file not found: $CONFIG_FILE"
            exit 1
        fi

        log_info "Configuration file: $CONFIG_FILE"
        echo

        local device_count=$(yq eval '.frr_config.devices | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
        if [[ "$device_count" == "0" ]]; then
            log_error "No devices found in configuration file"
            exit 1
        fi

        log_info "Found $device_count device(s) in configuration"

        for i in $(seq 0 $((device_count - 1))); do
            configure_device_from_config "$CONFIG_FILE" "$i"
        done
    else
        # VDC mode
        if [[ ! -f "$VDC_CONFIG" ]]; then
            log_error "VDC config file not found: $VDC_CONFIG"
            exit 1
        fi

        configure_from_vdc_topology "$VDC_CONFIG"
    fi

    echo
    log_success "FRR configuration completed!"
}

# Run main
main
