#!/bin/bash

###############################################################################
# Ubuntu OS Repacker - Dependency Installation Script
# Installs required tools for ISO repacking
###############################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_ubuntu_version() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS version"
        exit 1
    fi
    
    source /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "This script is designed for Ubuntu only (detected: $ID)"
        exit 1
    fi
    
    if [[ "$VERSION_ID" != "24.04" ]]; then
        log_error "This script requires Ubuntu 24.04 (detected: $VERSION_ID)"
        exit 1
    fi
    
    log_success "Detected Ubuntu $VERSION_ID"
}

install_dependencies() {
    log_info "Updating package lists..."
    apt-get update -qq
    
    log_info "Installing required dependencies..."
    
    # Required packages for ISO manipulation
    local packages=(
        xorriso
        squashfs-tools
        genisoimage
        isolinux
        syslinux-utils
        
        # Additional utilities
        rsync
        file
        wget
        curl
    )
    
    apt-get install -y "${packages[@]}"
    
    log_success "All dependencies installed successfully"
}

verify_installation() {
    log_info "Verifying installation..."
    
    local required_commands=(
        xorriso
        unsquashfs
        mksquashfs
        genisoimage
        chroot
        rsync
    )
    
    local missing=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Verification failed. Missing commands: ${missing[*]}"
        exit 1
    fi
    
    log_success "All required commands are available"
}

main() {
    log_info "Ubuntu OS Repacker - Dependency Installer"
    log_info "=========================================="
    
    check_root
    check_ubuntu_version
    install_dependencies
    verify_installation
    
    log_success "=========================================="
    log_success "Installation completed successfully!"
    log_info "You can now use the repack-os.sh script"
}

main
