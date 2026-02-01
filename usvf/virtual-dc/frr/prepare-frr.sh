#!/bin/bash
################################################################################
# FRR Preparation Tool
#
# Installs FRR packages and enables the FRR service on remote devices via SSH.
# This script prepares devices for FRR configuration without applying any
# BGP/routing configuration.
#
# Usage:
#   ./prepare-frr.sh -c <config.yaml> [options]
#   ./prepare-frr.sh --vdc-config <topology.yaml> [options]
#
# Options:
#   -c, --config FILE       FRR device configuration file (same format as configure-frr.sh)
#   --vdc-config FILE       Use VDC topology for device discovery
#   -d, --device NAME       Prepare specific device only
#   --dry-run               Show what would be done without executing
#   --ssh-key PATH          SSH private key for authentication
#   --ssh-password PASS     SSH password for authentication
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

# Print banner
print_banner() {
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║              FRR Preparation Tool                             ║
║                                                               ║
║  Install and enable FRRouting on remote devices via SSH      ║
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
    --vdc-config FILE       Use VDC topology for device discovery
    -d, --device NAME       Prepare specific device only (can be repeated)
    --dry-run               Show what would be done without executing
    --ssh-key PATH          SSH private key path (overrides config file)
    --ssh-password PASS     SSH password (overrides config file)
    --ssh-user USER         SSH username (default: ubuntu)
    -v, --verbose           Verbose output
    -h, --help              Show this help message

Examples:
    # Prepare all devices from standalone config
    $0 -c frr/examples/standalone-device.yaml

    # Prepare all VDC devices
    $0 --vdc-config config/topology.yaml

    # Dry-run to see what would be installed
    $0 --vdc-config config/topology.yaml --dry-run

    # Prepare specific device only
    $0 --vdc-config config/topology.yaml -d hypervisor-1

EOF
    exit 1
}

# Parse command line arguments
CONFIG_FILE=""
VDC_CONFIG=""
DRY_RUN=false
VERBOSE=false
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

# Install FRR on a remote device via SSH
# Usage: install_frr_on_device <host> <auth_credential> <auth_type> <user>
install_frr_on_device() {
    local host="$1"
    local auth_credential="$2"
    local auth_type="${3:-key}"
    local user="${4:-ubuntu}"

    log_info "Installing FRR on $host..."

    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

    # FRR installation script
    local install_script='
set -e
echo "Updating package lists..."
sudo apt-get update -qq

echo "Installing FRR and tools..."
sudo apt-get install -y -qq frr frr-pythontools

echo "Configuring FRR daemons..."
sudo tee /etc/frr/daemons > /dev/null << DAEMONS
zebra=yes
bgpd=yes
ospfd=no
ospf6d=no
ripd=no
ripngd=no
isisd=no
pimd=no
ldpd=no
nhrpd=no
eigrpd=no
babeld=no
sharpd=no
pbrd=no
bfdd=no
fabricd=no
vrrpd=no

vtysh_enable=yes
zebra_options="  -A 127.0.0.1 -s 90000000"
bgpd_options="   -A 127.0.0.1"
DAEMONS

echo "Enabling IP forwarding..."
sudo tee /etc/sysctl.d/99-forwarding.conf > /dev/null << SYSCTL
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
SYSCTL
sudo sysctl -p /etc/sysctl.d/99-forwarding.conf

echo "Enabling and starting FRR service..."
sudo systemctl enable frr
sudo systemctl restart frr

echo "FRR installation complete!"
sudo vtysh -c "show version" | head -3
'

    local result=0

    if [[ "$auth_type" == "key" ]]; then
        ssh $ssh_opts -i "$auth_credential" "${user}@${host}" "$install_script" 2>&1
        result=$?
    else
        sshpass -p "$auth_credential" ssh $ssh_opts "${user}@${host}" "$install_script" 2>&1
        result=$?
    fi

    if [[ $result -eq 0 ]]; then
        log_success "FRR installed and enabled on $host"
    else
        log_error "Failed to install FRR on $host"
    fi

    return $result
}

# Prepare device from standalone config
prepare_device_from_config() {
    local config_file="$1"
    local device_index="$2"

    local name=$(yq eval ".frr_config.devices[$device_index].name" "$config_file")
    local host=$(yq eval ".frr_config.devices[$device_index].host" "$config_file")

    if [[ -z "$name" || "$name" == "null" || -z "$host" || "$host" == "null" ]]; then
        log_warn "Skipping device at index $device_index - missing name or host"
        return 0
    fi

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
    log_info "Preparing device: $name ($host)"
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

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install FRR on $name ($host)"
        return 0
    fi

    if [[ -z "$auth_credential" ]]; then
        log_error "No SSH credentials available for $name"
        return 1
    fi

    # Wait for SSH
    if ! wait_for_ssh "$host" "$auth_credential" "$auth_type" 3 "$ssh_user"; then
        log_error "Cannot connect to $host via SSH"
        return 1
    fi

    # Install FRR
    install_frr_on_device "$host" "$auth_credential" "$auth_type" "$ssh_user"
}

# Prepare devices from VDC topology
prepare_from_vdc_topology() {
    local vdc_config="$1"

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
        ssh_key_path="$PROJECT_ROOT/config/vdc-${dc_name}/ssh-keys/id_rsa"
        if [[ ! -f "$ssh_key_path" ]]; then
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

        local mgmt_ip=$(echo "$device_info" | yq eval '.management.ip' - | cut -d'/' -f1)

        if [[ -z "$mgmt_ip" || "$mgmt_ip" == "null" ]]; then
            log_warn "No management IP for $device_name, skipping"
            continue
        fi

        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_info "Preparing device: $device_name ($mgmt_ip)"
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would install FRR on $device_name ($mgmt_ip)"
            continue
        fi

        # Wait for SSH
        if ! wait_for_ssh "$mgmt_ip" "$auth_credential" "$auth_type" 3 "$SSH_USER"; then
            log_warn "Cannot connect to $device_name at $mgmt_ip, skipping"
            continue
        fi

        # Install FRR
        install_frr_on_device "$mgmt_ip" "$auth_credential" "$auth_type" "$SSH_USER"
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
            prepare_device_from_config "$CONFIG_FILE" "$i"
        done
    else
        # VDC mode
        if [[ ! -f "$VDC_CONFIG" ]]; then
            log_error "VDC config file not found: $VDC_CONFIG"
            exit 1
        fi

        prepare_from_vdc_topology "$VDC_CONFIG"
    fi

    echo
    log_success "FRR preparation completed!"
    log_info "Next step: Run configure-frr.sh to apply BGP configuration"
}

# Run main
main
