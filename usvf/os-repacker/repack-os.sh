#!/bin/bash

###############################################################################
# Ubuntu OS Repacker - All-in-One Wrapper
# 
# This script provides backward compatibility by orchestrating Stage 1 and Stage 2.
# It internally calls stage1-packages.sh and stage2-network.sh to achieve the
# same result as the original monolithic script.
#
# Usage:
#   sudo ./repack-os.sh --iso INPUT.iso --output OUTPUT.iso [OPTIONS]
###############################################################################

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
INPUT_ISO=""
OUTPUT_ISO=""
ADDITIONAL_PACKAGES=""
LOCAL_ASN=""
ROUTER_ID=""
BGP_CONFIG_FILE=""
BGP_NETWORKS=""
WORK_DIR="/tmp/os-repack-$$"
VERBOSE=false

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

log_stage() {
    echo -e "${BLUE}[STAGE]${NC} $1"
}

show_help() {
    cat << EOF
Ubuntu OS Repacker - All-in-One ISO Customization Tool

Usage: sudo $0 [OPTIONS]

This script combines package installation and network configuration into a
single command. It internally uses stage1-packages.sh and stage2-network.sh
for a modular approach while maintaining backward compatibility.

Required Options:
  --iso FILE          Path to input Ubuntu 24.04 ISO file
  --output FILE       Path for output ISO file
  --local-asn ASN     Local BGP AS number (1-4294967295)
  --router-id IP      BGP router ID in IP address format (e.g., 1.1.1.1)

Optional Options:
  --packages LIST     Comma-separated list of additional packages to install
  --bgp-config FILE   BGP peers configuration file (format: remote_asn,remote_ip,local_ip)
  --bgp-networks LIST Networks to advertise via BGP (CIDR, comma-separated)
  --work-dir DIR      Custom working directory (default: /tmp/os-repack-PID)
  --verbose           Enable verbose output
  -h, --help          Show this help message

Default Packages Installed:
  - OpenStack components (python3-openstackclient, clients, etc.)
  - FRR routing daemon (frr, frr-pythontools)
  - Network tools (net-tools, iproute2, ethtool, etc.)
  - Debugging tools (tcpdump, strace, sysstat, htop, etc.)
  - Development tools (build-essential, git, python3-pip, etc.)
  - System utilities (vim, tmux, rsync, etc.)

BGP Configuration:
  - Mellanox interfaces are auto-detected on first boot
  - BGP peers are auto-assigned to Mellanox interfaces in detection order
  - By default, NO networks are advertised unless specified with --bgp-networks

Examples:
  # Basic usage with default packages
  sudo $0 \\
    --iso ubuntu-24.04.iso \\
    --output custom-ubuntu.iso \\
    --local-asn 65001 \\
    --router-id 10.0.0.1

  # With custom packages and BGP configuration
  sudo $0 \\
    --iso ubuntu-24.04.iso \\
    --output custom-ubuntu.iso \\
    --local-asn 65001 \\
    --router-id 10.0.0.1 \\
    --packages "docker.io,vim,htop" \\
    --bgp-config bgp-peers.conf \\
    --bgp-networks "10.0.0.0/24,192.168.1.0/24"

Advanced Usage:
  For more granular control, use the individual stage scripts:
  
  # Stage 1: Install packages only
  sudo ./stage1-packages.sh --iso ubuntu.iso --output base.iso --packages "..."
  
  # Stage 2: Add network config to existing ISO
  sudo ./stage2-network.sh \\
    --iso base.iso \\
    --output final.iso \\
    --local-asn 65001 \\
    --router-id 10.0.0.1 \\
    --bgp-config bgp-peers.conf

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
        --packages)
            ADDITIONAL_PACKAGES="$2"
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

if [[ -z "$INPUT_ISO" ]]; then
    log_error "Input ISO file is required (--iso)"
    show_help
    exit 1
fi

if [[ -z "$OUTPUT_ISO" ]]; then
    log_error "Output ISO file is required (--output)"
    show_help
    exit 1
fi

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

if [[ ! -f "$INPUT_ISO" ]]; then
    log_error "Input ISO file not found: $INPUT_ISO"
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

# Verify stage scripts exist
if [[ ! -f "${SCRIPT_DIR}/stage1-packages.sh" ]]; then
    log_error "Stage 1 script not found: ${SCRIPT_DIR}/stage1-packages.sh"
    exit 1
fi

if [[ ! -f "${SCRIPT_DIR}/stage2-network.sh" ]]; then
    log_error "Stage 2 script not found: ${SCRIPT_DIR}/stage2-network.sh"
    exit 1
fi

###############################################################################
# Main Execution
###############################################################################

log_info "============================================="
log_info "Ubuntu OS Repacker - All-in-One Mode"
log_info "============================================="
log_info "This script orchestrates a two-stage process:"
log_info "  Stage 1: Package installation"
log_info "  Stage 2: Network & BGP configuration"
log_info ""
log_info "Input ISO:  $INPUT_ISO"
log_info "Output ISO: $OUTPUT_ISO"
log_info "Local ASN:  $LOCAL_ASN"
log_info "Router ID:  $ROUTER_ID"
if [[ -n "$ADDITIONAL_PACKAGES" ]]; then
    log_info "Additional Packages: $ADDITIONAL_PACKAGES"
fi
if [[ -n "$BGP_CONFIG_FILE" ]]; then
    log_info "BGP Config: $BGP_CONFIG_FILE"
fi
if [[ -n "$BGP_NETWORKS" ]]; then
    log_info "BGP Networks: $BGP_NETWORKS"
fi
log_info "Work Dir:   $WORK_DIR"
echo

# Create work directory
mkdir -p "$WORK_DIR"

# Temporary ISO between stages
TEMP_ISO="${WORK_DIR}/stage1-output.iso"

# Cleanup function
cleanup() {
    local exit_code=$?
    log_info "Cleaning up temporary files..."
    
    # Remove temporary ISO
    if [[ -f "$TEMP_ISO" ]]; then
        rm -f "$TEMP_ISO"
    fi
    
    # Remove work directory
    if [[ -d "$WORK_DIR" ]] && [[ "$WORK_DIR" == /tmp/* ]]; then
        rm -rf "$WORK_DIR"
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        log_info "======================================"
        log_info "All-in-One Repack Completed Successfully!"
        log_info "======================================"
        log_info "Output ISO: $OUTPUT_ISO"
    else
        log_error "Repack failed with exit code $exit_code"
    fi
    
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Execute Stage 1: Package Installation
log_stage "═══════════════════════════════════════════"
log_stage "STAGE 1: Package Installation"
log_stage "═══════════════════════════════════════════"
echo

STAGE1_CMD=(
    "${SCRIPT_DIR}/stage1-packages.sh"
    --iso "$INPUT_ISO"
    --output "$TEMP_ISO"
    --work-dir "${WORK_DIR}/stage1"
)

if [[ -n "$ADDITIONAL_PACKAGES" ]]; then
    STAGE1_CMD+=(--packages "$ADDITIONAL_PACKAGES")
fi

if [[ "$VERBOSE" == "true" ]]; then
    STAGE1_CMD+=(--verbose)
fi

# Execute Stage 1
"${STAGE1_CMD[@]}"

echo
log_stage "Stage 1 Complete - Intermediate ISO created"
echo

# Execute Stage 2: Network & BGP Configuration
log_stage "═══════════════════════════════════════════"
log_stage "STAGE 2: Network & BGP Configuration"
log_stage "═══════════════════════════════════════════"
echo

STAGE2_CMD=(
    "${SCRIPT_DIR}/stage2-network.sh"
    --iso "$TEMP_ISO"
    --output "$OUTPUT_ISO"
    --local-asn "$LOCAL_ASN"
    --router-id "$ROUTER_ID"
    --work-dir "${WORK_DIR}/stage2"
)

if [[ -n "$BGP_CONFIG_FILE" ]]; then
    STAGE2_CMD+=(--bgp-config "$BGP_CONFIG_FILE")
fi

if [[ -n "$BGP_NETWORKS" ]]; then
    STAGE2_CMD+=(--bgp-networks "$BGP_NETWORKS")
fi

if [[ "$VERBOSE" == "true" ]]; then
    STAGE2_CMD+=(--verbose)
fi

# Execute Stage 2
"${STAGE2_CMD[@]}"

echo
log_stage "Stage 2 Complete - Final ISO created"
echo

# Success message will be printed by cleanup trap
