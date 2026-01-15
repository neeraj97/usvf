#!/bin/bash

###############################################################################
# Ubuntu OS Repacker - Stage 2: Network & BGP Configuration (Cloud-Init Mode)
# 
# This script adds network configuration using cloud-init.
# Two modes available:
#   1. ISO Mode: Embed cloud-init into ISO
#   2. Cloud-Init Only Mode: Generate cloud-init files only (no ISO needed)
#
# Usage:
#   sudo ./stage2-network.sh --iso INPUT.iso --output OUTPUT.iso [OPTIONS]
#   sudo ./stage2-network.sh --cloud-init-only --output-dir DIR [OPTIONS]
###############################################################################

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source modules
source "${SCRIPT_DIR}/modules/iso-extract.sh"
source "${SCRIPT_DIR}/modules/iso-repack.sh"
source "${SCRIPT_DIR}/modules/cloud-init-generator.sh"

# Default values
INPUT_ISO=""
OUTPUT_ISO=""
OUTPUT_DIR=""
LOCAL_ASN=""
ROUTER_ID=""
BGP_CONFIG_FILE=""
BGP_NETWORKS=""
WORK_DIR="/tmp/stage2-repack-$$"
VERBOSE=false
CLOUD_INIT_ONLY=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###############################################################################
# Helper Functions
###############################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${BLUE}[SUCCESS]${NC} $1"
}

show_help() {
    cat << EOF
Ubuntu OS Repacker - Stage 2: Network & BGP Configuration (Cloud-Init Mode)

Usage: 
  # ISO Mode (embed cloud-init into ISO)
  sudo $0 --iso INPUT.iso --output OUTPUT.iso [OPTIONS]
  
  # Cloud-Init Only Mode (generate cloud-init files without ISO)
  sudo $0 --cloud-init-only --output-dir DIR [OPTIONS]

This stage adds network configuration using cloud-init.
It configures Mellanox interface detection and BGP routing.

Required Options (ISO Mode):
  --iso FILE          Path to input ISO file (can be Stage 1 output or any Ubuntu ISO)
  --output FILE       Path for output ISO file
  --local-asn ASN     Local BGP AS number (1-4294967295)
  --router-id IP      BGP router ID in IP address format (e.g., 1.1.1.1)

Required Options (Cloud-Init Only Mode):
  --cloud-init-only   Generate cloud-init files only (no ISO processing)
  --output-dir DIR    Directory to save cloud-init files
  --local-asn ASN     Local BGP AS number (1-4294967295)
  --router-id IP      BGP router ID in IP address format

Optional Options (Both Modes):
  --bgp-config FILE   BGP peers configuration file (format: remote_asn,remote_ip,local_ip)
  --bgp-networks LIST Networks to advertise via BGP (CIDR, comma-separated)
  --work-dir DIR      Custom working directory (ISO mode only, default: /tmp/stage2-repack-PID)
  --verbose           Enable verbose output
  -h, --help          Show this help message

BGP Configuration:
  The --bgp-config file should contain one peer per line in format:
    remote_asn,remote_ip,local_ip
  
  Peers are automatically assigned to detected Mellanox interfaces in order.
  First peer → First Mellanox interface, Second peer → Second Mellanox interface, etc.

Network Advertisement:
  Use --bgp-networks to specify which networks to advertise.
  Format: Comma-separated CIDR notation
  Example: --bgp-networks "10.0.0.0/24,192.168.1.0/24"
  
  IMPORTANT: By default, NO networks are advertised unless specified.

Cloud-Init Mode:
  This version uses cloud-init for configuration instead of systemd services.
  All detection and configuration scripts are embedded in cloud-init user-data.
  Benefits:
    - Industry standard (cloud-init)
    - Better debugging (cloud-init logs)
    - More extensible (full cloud-init ecosystem)
    - Simpler architecture (no systemd services needed)

Examples:

  # ISO Mode: Basic BGP configuration embedded in ISO
  sudo $0 \\
    --iso base-ubuntu.iso \\
    --output final-ubuntu.iso \\
    --local-asn 65001 \\
    --router-id 10.0.0.1

  # ISO Mode: With BGP peers and network advertisement
  sudo $0 \\
    --iso base-ubuntu.iso \\
    --output final-ubuntu.iso \\
    --local-asn 65001 \\
    --router-id 10.0.0.1 \\
    --bgp-config bgp-peers.conf \\
    --bgp-networks "10.0.0.0/24,192.168.1.0/24"

  # Cloud-Init Only Mode: Generate files for external use
  sudo $0 \\
    --cloud-init-only \\
    --output-dir /tmp/cloud-init-bgp \\
    --local-asn 65001 \\
    --router-id 10.0.0.1 \\
    --bgp-config bgp-peers.conf \\
    --bgp-networks "10.0.0.0/24"

  # Then use generated files with cloud-localds or ConfigDrive
  cloud-localds config.iso /tmp/cloud-init-bgp/user-data /tmp/cloud-init-bgp/meta-data

  # Multiple datacenters from same base ISO
  sudo $0 --iso base.iso --output dc1.iso --local-asn 65001 --router-id 10.1.0.1 --bgp-config dc1-peers.conf
  sudo $0 --iso base.iso --output dc2.iso --local-asn 65002 --router-id 10.2.0.1 --bgp-config dc2-peers.conf

  # Generate cloud-init for different datacenters (reuse with any Ubuntu)
  sudo $0 --cloud-init-only --output-dir dc1-config --local-asn 65001 --router-id 10.1.0.1 --bgp-config dc1-peers.conf
  sudo $0 --cloud-init-only --output-dir dc2-config --local-asn 65002 --router-id 10.2.0.1 --bgp-config dc2-peers.conf

EOF
}

validate_asn() {
    local asn=$1
    if ! [[ "$asn" =~ ^[0-9]+$ ]]; then
        log_error "Invalid ASN: $asn (must be a number)"
        return 1
    fi
    if [[ $asn -lt 1 ]] || [[ $asn -gt 4294967295 ]]; then
        log_error "ASN out of range: $asn (must be between 1 and 4294967295)"
        return 1
    fi
    return 0
}

validate_ip() {
    local ip=$1
    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_error "Invalid IP address format: $ip"
        return 1
    fi
    
    IFS='.' read -ra OCTETS <<< "$ip"
    for octet in "${OCTETS[@]}"; do
        if [[ $octet -gt 255 ]]; then
            log_error "Invalid IP address: $ip (octet $octet > 255)"
            return 1
        fi
    done
    return 0
}

###############################################################################
# Parse Arguments
###############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --iso)
            INPUT_ISO="$2"
            shift 2
            ;;
        --output)
            OUTPUT_ISO="$2"
            shift 2
            ;;
        --cloud-init-only)
            CLOUD_INIT_ONLY=true
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --local-asn)
            LOCAL_ASN="$2"
            shift 2
            ;;
        --router-id)
            ROUTER_ID="$2"
            shift 2
            ;;
        --bgp-config)
            BGP_CONFIG_FILE="$2"
            shift 2
            ;;
        --bgp-networks)
            BGP_NETWORKS="$2"
            shift 2
            ;;
        --work-dir)
            WORK_DIR="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

###############################################################################
# Validate Arguments
###############################################################################

if [[ "$CLOUD_INIT_ONLY" == true ]]; then
    # Cloud-Init Only Mode validation
    if [[ -z "$OUTPUT_DIR" ]]; then
        log_error "Output directory is required in cloud-init-only mode (--output-dir)"
        show_help
        exit 1
    fi
else
    # ISO Mode validation
    if [[ -z "$INPUT_ISO" ]]; then
        log_error "Input ISO file is required in ISO mode (--iso)"
        show_help
        exit 1
    fi
    
    if [[ -z "$OUTPUT_ISO" ]]; then
        log_error "Output ISO file is required in ISO mode (--output)"
        show_help
        exit 1
    fi
    
    if [[ ! -f "$INPUT_ISO" ]]; then
        log_error "Input ISO file not found: $INPUT_ISO"
        exit 1
    fi
fi

# Common validation
if [[ -z "$LOCAL_ASN" ]]; then
    log_error "Local ASN is required (--local-asn)"
    show_help
    exit 1
fi

if [[ -z "$ROUTER_ID" ]]; then
    log_error "Router ID is required (--router-id)"
    show_help
    exit 1
fi

if ! validate_asn "$LOCAL_ASN"; then
    exit 1
fi

if ! validate_ip "$ROUTER_ID"; then
    exit 1
fi

if [[ -n "$BGP_CONFIG_FILE" ]] && [[ ! -f "$BGP_CONFIG_FILE" ]]; then
    log_error "BGP configuration file not found: $BGP_CONFIG_FILE"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Verify OS version (warning only)
if ! grep -q "Ubuntu 24.04" /etc/os-release 2>/dev/null; then
    log_warn "This script is designed for Ubuntu 24.04"
    log_warn "Current OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
fi

###############################################################################
# Cloud-Init Only Mode
###############################################################################

if [[ "$CLOUD_INIT_ONLY" == true ]]; then
    log_info "Cloud-Init Only Mode - Generating cloud-init files"
    log_info "=================================================="
    log_info "Output Dir:  $OUTPUT_DIR"
    log_info "Local ASN:   $LOCAL_ASN"
    log_info "Router ID:   $ROUTER_ID"
    if [[ -n "$BGP_CONFIG_FILE" ]]; then
        log_info "BGP Config:  $BGP_CONFIG_FILE"
    fi
    if [[ -n "$BGP_NETWORKS" ]]; then
        log_info "BGP Networks: $BGP_NETWORKS"
    else
        log_warn "No BGP networks specified - no routes will be advertised"
    fi
    echo
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Generate cloud-init user-data
    log_info "Generating cloud-init user-data..."
    generate_cloud_init_userdata \
        "$LOCAL_ASN" \
        "$ROUTER_ID" \
        "$BGP_CONFIG_FILE" \
        "$BGP_NETWORKS" \
        "${OUTPUT_DIR}/user-data"
    
    # Generate cloud-init meta-data
    log_info "Generating cloud-init meta-data..."
    generate_cloud_init_metadata "${OUTPUT_DIR}/meta-data"
    
    echo
    log_success "Cloud-init files generated successfully!"
    log_info ""
    log_info "Generated files:"
    log_info "  - ${OUTPUT_DIR}/user-data"
    log_info "  - ${OUTPUT_DIR}/meta-data"
    log_info ""
    log_info "Usage options:"
    log_info ""
    log_info "1. Create NoCloud ISO:"
    log_info "   cloud-localds config.iso ${OUTPUT_DIR}/user-data ${OUTPUT_DIR}/meta-data"
    log_info "   # Then boot Ubuntu with both ISOs attached"
    log_info ""
    log_info "2. Copy to NoCloud directory in existing system:"
    log_info "   sudo mkdir -p /var/lib/cloud/seed/nocloud-net/"
    log_info "   sudo cp ${OUTPUT_DIR}/user-data /var/lib/cloud/seed/nocloud-net/"
    log_info "   sudo cp ${OUTPUT_DIR}/meta-data /var/lib/cloud/seed/nocloud-net/"
    log_info "   sudo cloud-init clean"
    log_info "   sudo cloud-init init"
    log_info ""
    log_info "3. Use with HTTP datasource (setup web server first):"
    log_info "   Boot with: ds=nocloud-net;s=http://your-server/"
    log_info ""
    log_info "4. Embed in Stage 2 ISO (use regular mode instead)"
    
    exit 0
fi

###############################################################################
# ISO Mode - Main Execution
###############################################################################

log_info "Ubuntu OS Repacker - Stage 2: Network & BGP Configuration (Cloud-Init Mode)"
log_info "============================================================================"
log_info "Input ISO:  $INPUT_ISO"
log_info "Output ISO: $OUTPUT_ISO"
log_info "Local ASN:  $LOCAL_ASN"
log_info "Router ID:  $ROUTER_ID"
log_info "Work Dir:   $WORK_DIR"
if [[ -n "$BGP_CONFIG_FILE" ]]; then
    log_info "BGP Config: $BGP_CONFIG_FILE"
fi
if [[ -n "$BGP_NETWORKS" ]]; then
    log_info "BGP Networks: $BGP_NETWORKS"
else
    log_warn "No BGP networks specified - no routes will be advertised"
fi
echo

# Create work directory
mkdir -p "$WORK_DIR"

# Cleanup function
cleanup() {
    local exit_code=$?
    log_info "Cleaning up..."
    
    # Unmount if still mounted
    if mountpoint -q "${WORK_DIR}/squashfs_extract/dev" 2>/dev/null; then
        umount "${WORK_DIR}/squashfs_extract/dev" 2>/dev/null || true
    fi
    if mountpoint -q "${WORK_DIR}/squashfs_extract/proc" 2>/dev/null; then
        umount "${WORK_DIR}/squashfs_extract/proc" 2>/dev/null || true
    fi
    if mountpoint -q "${WORK_DIR}/squashfs_extract/sys" 2>/dev/null; then
        umount "${WORK_DIR}/squashfs_extract/sys" 2>/dev/null || true
    fi
    if mountpoint -q "${WORK_DIR}/iso_extract" 2>/dev/null; then
        umount "${WORK_DIR}/iso_extract" 2>/dev/null || true
    fi
    
    # Remove work directory
    if [[ -d "$WORK_DIR" ]] && [[ "$WORK_DIR" == /tmp/* ]]; then
        rm -rf "$WORK_DIR"
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "Stage 2 completed successfully!"
    else
        log_error "Stage 2 failed with exit code $exit_code"
    fi
    
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Step 1: Extract ISO
log_info "Step 1: Extracting ISO..."
extract_iso "$INPUT_ISO" "$WORK_DIR"
echo

# Step 2: Generate cloud-init files
log_info "Step 2: Generating cloud-init configuration..."
CLOUD_INIT_DIR="${WORK_DIR}/squashfs_extract/var/lib/cloud/seed/nocloud-net"
mkdir -p "$CLOUD_INIT_DIR"

generate_cloud_init_userdata \
    "$LOCAL_ASN" \
    "$ROUTER_ID" \
    "$BGP_CONFIG_FILE" \
    "$BGP_NETWORKS" \
    "${CLOUD_INIT_DIR}/user-data"

generate_cloud_init_metadata "${CLOUD_INIT_DIR}/meta-data"

log_info "Cloud-init files embedded at: $CLOUD_INIT_DIR"
echo

# Step 3: Ensure cloud-init is enabled
log_info "Step 3: Configuring cloud-init..."
if [[ -f "${WORK_DIR}/squashfs_extract/etc/cloud/cloud.cfg" ]]; then
    log_info "Cloud-init configuration found"
    
    # Ensure NoCloud datasource is enabled
    if ! grep -q "NoCloud" "${WORK_DIR}/squashfs_extract/etc/cloud/cloud.cfg.d/"* 2>/dev/null; then
        cat > "${WORK_DIR}/squashfs_extract/etc/cloud/cloud.cfg.d/90_nocloud.cfg" << 'EOF'
# NoCloud datasource configuration
datasource_list: [ NoCloud, None ]
datasource:
  NoCloud:
    # Look for cloud-init data in /var/lib/cloud/seed/nocloud-net/
    seedfrom: /var/lib/cloud/seed/nocloud-net/
EOF
        log_info "NoCloud datasource configured"
    fi
else
    log_warn "Cloud-init not found - ensure it's installed in Stage 1"
fi
echo

# Step 4: Repack ISO
log_info "Step 4: Repacking ISO..."
repack_iso "$WORK_DIR" "$OUTPUT_ISO"
echo

log_success "Stage 2 Network Configuration Complete!"
log_info ""
log_info "Output ISO: $OUTPUT_ISO"
log_info ""
log_info "Configuration Summary:"
log_info "  - Mode: Cloud-Init Embedded"
log_info "  - Local ASN: $LOCAL_ASN"
log_info "  - Router ID: $ROUTER_ID"
if [[ -n "$BGP_NETWORKS" ]]; then
    log_info "  - Networks advertised: $BGP_NETWORKS"
else
    log_info "  - Networks advertised: NONE"
fi
log_info ""
log_info "Deployment Notes:"
log_info "  - Cloud-init will run on first boot"
log_info "  - Mellanox interfaces will be auto-detected"
log_info "  - BGP will be configured automatically"
log_info "  - Configuration logs: /var/log/cloud-init-output.log"
log_info ""
log_info "Debugging after deployment:"
log_info "  cloud-init status"
log_info "  cat /var/log/cloud-init-output.log"
log_info "  cat /var/log/network-setup.log"
log_info "  sudo vtysh -c 'show ip bgp summary'"
log_info "  sudo vtysh -c 'show ip bgp neighbors'"
