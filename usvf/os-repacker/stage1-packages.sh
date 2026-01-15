#!/bin/bash

###############################################################################
# Ubuntu OS Repacker - Stage 1: Package Installation
# 
# This script creates a base Ubuntu ISO with pre-installed packages.
# Stage 1 focuses solely on package installation without network configuration.
#
# Usage:
#   sudo ./stage1-packages.sh --iso INPUT.iso --output OUTPUT.iso [OPTIONS]
###############################################################################

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source modules
source "${SCRIPT_DIR}/modules/iso-extract.sh"
source "${SCRIPT_DIR}/modules/package-install.sh"
source "${SCRIPT_DIR}/modules/iso-repack.sh"

# Default values
INPUT_ISO=""
OUTPUT_ISO=""
ADDITIONAL_PACKAGES=""
WORK_DIR="/tmp/stage1-repack-$$"
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

show_help() {
    cat << EOF
Ubuntu OS Repacker - Stage 1: Package Installation

Usage: sudo $0 [OPTIONS]

This stage creates a base Ubuntu ISO with pre-installed packages.
No network configuration is performed at this stage.

Required Options:
  --iso FILE          Path to input Ubuntu 24.04 ISO file
  --output FILE       Path for output ISO file

Optional Options:
  --packages LIST     Comma-separated list of additional packages to install
  --work-dir DIR      Custom working directory (default: /tmp/stage1-repack-PID)
  --verbose           Enable verbose output
  -h, --help          Show this help message

Default Packages Installed:
  - OpenStack components (python3-openstackclient, clients, etc.)
  - FRR routing daemon (frr, frr-pythontools)
  - Network tools (net-tools, iproute2, ethtool, etc.)
  - Debugging tools (tcpdump, strace, sysstat, htop, etc.)
  - Development tools (build-essential, git, python3-pip, etc.)
  - System utilities (vim, tmux, rsync, etc.)

Examples:
  # Basic usage with default packages
  sudo $0 --iso ubuntu-24.04.iso --output base-ubuntu.iso

  # Add custom packages
  sudo $0 \\
    --iso ubuntu-24.04.iso \\
    --output base-ubuntu.iso \\
    --packages "docker.io,kubernetes,ansible"

  # Use custom work directory
  sudo $0 \\
    --iso ubuntu-24.04.iso \\
    --output base-ubuntu.iso \\
    --work-dir /mnt/ssd/work \\
    --verbose

EOF
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

if [[ ! -f "$INPUT_ISO" ]]; then
    log_error "Input ISO file not found: $INPUT_ISO"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Verify OS version
if ! grep -q "Ubuntu 24.04" /etc/os-release 2>/dev/null; then
    log_warn "This script is designed for Ubuntu 24.04"
    log_warn "Current OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

###############################################################################
# Main Execution
###############################################################################

log_info "Ubuntu OS Repacker - Stage 1: Package Installation"
log_info "=================================================="
log_info "Input ISO:  $INPUT_ISO"
log_info "Output ISO: $OUTPUT_ISO"
log_info "Work Dir:   $WORK_DIR"
if [[ -n "$ADDITIONAL_PACKAGES" ]]; then
    log_info "Additional Packages: $ADDITIONAL_PACKAGES"
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
        log_info "Stage 1 completed successfully!"
    else
        log_error "Stage 1 failed with exit code $exit_code"
    fi
    
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Stage 1: Extract ISO
log_info "Step 1: Extracting ISO..."
extract_iso "$INPUT_ISO" "$WORK_DIR"
echo

# Stage 2: Install Packages
log_info "Step 2: Installing packages..."
install_packages "$WORK_DIR" "$ADDITIONAL_PACKAGES"
echo

# Stage 3: Repack ISO
log_info "Step 3: Repacking ISO..."
repack_iso "$WORK_DIR" "$OUTPUT_ISO"
echo

log_info "Stage 1 Package Installation Complete!"
log_info "Output ISO: $OUTPUT_ISO"
log_info ""
log_info "Next Steps:"
log_info "  - Use Stage 2 (stage2-network.sh) to add network configuration"
log_info "  - Or deploy this base ISO directly if network config not needed"
