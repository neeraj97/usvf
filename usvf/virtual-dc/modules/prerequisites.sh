#!/bin/bash
################################################################################
# Prerequisites Checking Module
#
# Checks and installs required dependencies for virtual DC deployment:
# - KVM/QEMU virtualization tools
# - Network tools (bridge-utils, iproute2)
# - YAML parser (yq)
# - FRRouting for BGP
################################################################################

check_prerequisites() {
    log_info "Checking system prerequisites..."
    
    local virtualization_ok=true
    local interactive_mode="${INTERACTIVE_INSTALL:-true}"
    
    # Check operating system - Ubuntu 24.04 only
    if [[ "$(uname)" != "Linux" ]]; then
        log_error "Unsupported operating system: $(uname)"
        log_error "This tool requires Linux (Ubuntu 24.04 LTS recommended)"
        return 1
    fi
    
    # Check for Ubuntu
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" ]]; then
            log_success "✓ Running on Ubuntu $VERSION_ID"
            if [[ "$VERSION_ID" != "24.04" ]]; then
                log_warn "Warning: Ubuntu 24.04 LTS is recommended, you are running $VERSION_ID"
            fi
        else
            log_warn "Warning: Ubuntu 24.04 LTS is recommended, detected: $ID $VERSION_ID"
        fi
    fi
    
    echo ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "  Checking Required Tools"
    log_info "═══════════════════════════════════════════════════════"
    echo ""
    
    # Check for required tools with interactive installation
    check_and_install_tool "yq" "YAML parser" "yq_install"
    check_and_install_tool "jq" "JSON processor" "apt_install" "jq"
    check_and_install_tool "virsh" "KVM management" "apt_install" "libvirt-daemon-system libvirt-clients"
    check_and_install_tool "virt-install" "VM installation" "apt_install" "virtinst"
    check_and_install_tool "qemu-img" "Disk image management" "apt_install" "qemu-kvm qemu-utils"
    check_and_install_tool "wget" "File download" "apt_install" "wget"
    check_and_install_tool "curl" "File download" "apt_install" "curl"
    check_and_install_tool "ip" "Network configuration" "apt_install" "iproute2"
    check_and_install_tool "ssh" "SSH client" "apt_install" "openssh-client"
    check_and_install_tool "ssh-keygen" "SSH key generation" "apt_install" "openssh-client"
    check_and_install_tool "genisoimage" "ISO creation" "apt_install" "genisoimage"
    check_and_install_tool "cloud-localds" "Cloud-init" "apt_install" "cloud-image-utils"
    check_and_install_tool "mkpasswd" "Password hashing" "apt_install" "whois"
    
    echo ""
    log_info "═══════════════════════════════════════════════════════"
    log_info "  Checking System Configuration"
    log_info "═══════════════════════════════════════════════════════"
    echo ""
    
    # Check virtualization support
    if ! check_virtualization_support; then
        virtualization_ok=false
        log_error "✗ Hardware virtualization is not enabled or not supported"
        log_error "  Please enable VT-x/AMD-V in BIOS settings"
    else
        log_success "✓ Hardware virtualization is enabled"
    fi
    
    # Check libvirt daemon
    if command -v virsh &> /dev/null; then
        if ! virsh list &> /dev/null 2>&1; then
            log_warn "✗ libvirt daemon is not running or not accessible"
            
            if [[ "$interactive_mode" == "true" ]]; then
                echo ""
                read -p "Would you like to start the libvirt daemon? (y/N): " -n 1 -r
                echo ""
                
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Starting libvirt daemon..."
                    sudo systemctl enable libvirtd
                    sudo systemctl start libvirtd
                    
                    if virsh list &> /dev/null 2>&1; then
                        log_success "✓ libvirt daemon started successfully"
                    else
                        log_error "Failed to start libvirt daemon"
                        log_info "You may need to add your user to libvirt group:"
                        log_info "  sudo usermod -aG libvirt $USER"
                        log_info "  Then log out and back in"
                    fi
                fi
            else
                log_info "Run: sudo systemctl start libvirtd"
            fi
        else
            log_success "✓ libvirt daemon is running"
        fi
    fi
    
    if [[ "$virtualization_ok" == "false" ]]; then
        return 1
    fi
    
    echo ""
    
    # Check disk space
    check_disk_space
    
    # Check network capabilities
    check_network_capabilities
    
    # Check and download Ubuntu 24.04 images
    check_ubuntu_images
    
    echo ""
    log_success "═══════════════════════════════════════════════════════"
    log_success "  All prerequisites are met!"
    log_success "═══════════════════════════════════════════════════════"
    echo ""
    
    return 0
}

check_ubuntu_images() {
    log_info "Checking Ubuntu 24.04 cloud images..."
    
    local images_dir="${SCRIPT_DIR}/../images"
    local ubuntu_image="${images_dir}/ubuntu-24.04-server-cloudimg-amd64.img"
    local ubuntu_url="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    
    # Create images directory if it doesn't exist
    mkdir -p "$images_dir"
    
    if [[ -f "$ubuntu_image" ]]; then
        local image_size=$(du -h "$ubuntu_image" | cut -f1)
        log_success "✓ Ubuntu 24.04 cloud image exists (${image_size})"
        
        # Check if image is recent (less than 30 days old)
        local image_age=$(( ($(date +%s) - $(stat -c %Y "$ubuntu_image")) / 86400 ))
        
        if [[ $image_age -gt 30 ]]; then
            log_warn "Ubuntu image is ${image_age} days old. Consider updating it."
            log_info "Run: rm $ubuntu_image && ./deploy-virtual-dc.sh --check-prereqs"
        fi
    else
        log_info "Ubuntu 24.04 cloud image not found. Downloading..."
        download_ubuntu_image "$ubuntu_url" "$ubuntu_image"
    fi
}

download_ubuntu_image() {
    local url="$1"
    local dest="$2"
    local temp_file="${dest}.tmp"
    
    log_info "Downloading Ubuntu 24.04 Noble Numbat cloud image..."
    log_info "Source: $url"
    log_info "Destination: $dest"
    log_warn "This may take several minutes depending on your internet connection..."
    
    # Download with progress
    if command -v wget &> /dev/null; then
        wget --show-progress -O "$temp_file" "$url"
    elif command -v curl &> /dev/null; then
        curl -L --progress-bar -o "$temp_file" "$url"
    else
        log_error "Neither wget nor curl available for download"
        return 1
    fi
    
    if [[ $? -eq 0 ]] && [[ -f "$temp_file" ]]; then
        mv "$temp_file" "$dest"
        log_success "✓ Ubuntu 24.04 cloud image downloaded successfully"
        
        # Verify image
        local image_size=$(du -h "$dest" | cut -f1)
        log_info "Image size: ${image_size}"
        
        # Verify it's a valid qcow2 image
        if command -v qemu-img &> /dev/null; then
            if qemu-img info "$dest" &> /dev/null; then
                log_success "✓ Image verified as valid QCOW2 format"
            else
                log_error "Downloaded image appears to be corrupted"
                rm -f "$dest"
                return 1
            fi
        fi
    else
        log_error "Failed to download Ubuntu image"
        rm -f "$temp_file"
        return 1
    fi
}

prepare_vm_image() {
    local base_image="$1"
    local vm_name="$2"
    local vm_disk_size="${3:-50G}"
    local output_image="${SCRIPT_DIR}/../images/${vm_name}.qcow2"
    
    log_info "Preparing VM disk image for $vm_name..."
    
    # Create a copy of the base image
    qemu-img create -f qcow2 -F qcow2 -b "$base_image" "$output_image" "$vm_disk_size"
    
    if [[ $? -eq 0 ]]; then
        log_success "✓ VM disk created: $output_image"
        echo "$output_image"
        return 0
    else
        log_error "Failed to create VM disk image"
        return 1
    fi
}

check_and_install_tool() {
    local tool_name="$1"
    local tool_desc="$2"
    local install_type="$3"
    local install_packages="$4"
    local interactive_mode="${INTERACTIVE_INSTALL:-true}"
    
    if command -v "$tool_name" &> /dev/null; then
        local version=$(get_tool_version "$tool_name")
        log_success "✓ $tool_desc ($tool_name) $version"
        return 0
    else
        log_warn "✗ $tool_desc ($tool_name) is not installed"
        
        if [[ "$interactive_mode" == "true" ]]; then
            echo ""
            read -p "  Would you like to install $tool_desc now? (y/N): " -n 1 -r
            echo ""
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                case "$install_type" in
                    apt_install)
                        install_via_apt "$tool_desc" "$install_packages"
                        ;;
                    yq_install)
                        install_yq
                        ;;
                    *)
                        log_error "Unknown installation type: $install_type"
                        return 1
                        ;;
                esac
                
                # Verify installation
                if command -v "$tool_name" &> /dev/null; then
                    log_success "✓ $tool_desc installed successfully"
                    return 0
                else
                    log_error "✗ $tool_desc installation may have failed"
                    return 1
                fi
            else
                log_info "  Skipping $tool_desc installation"
                return 1
            fi
        else
            # Non-interactive mode - just report
            log_info "  Install with: "
            case "$install_type" in
                apt_install)
                    log_info "    sudo apt install -y $install_packages"
                    ;;
                yq_install)
                    log_info "    sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq"
                    log_info "    sudo chmod +x /usr/local/bin/yq"
                    ;;
            esac
            return 1
        fi
    fi
}

install_via_apt() {
    local tool_desc="$1"
    local packages="$2"
    
    log_info "  Installing $tool_desc..."
    
    # Update package list if not updated recently
    local apt_cache_age=0
    if [[ -f /var/cache/apt/pkgcache.bin ]]; then
        apt_cache_age=$(( ($(date +%s) - $(stat -c %Y /var/cache/apt/pkgcache.bin)) / 3600 ))
    fi
    
    if [[ $apt_cache_age -gt 24 ]]; then
        log_info "  Updating package cache..."
        sudo apt-get update -qq
    fi
    
    # Install packages
    sudo apt-get install -y $packages
    
    if [[ $? -eq 0 ]]; then
        log_success "  ✓ Installation completed"
        
        # Special handling for libvirt
        if [[ "$packages" == *"libvirt"* ]]; then
            log_info "  Adding user to libvirt and kvm groups..."
            sudo usermod -aG libvirt "$USER"
            sudo usermod -aG kvm "$USER"
            sudo systemctl enable libvirtd
            sudo systemctl start libvirtd
            log_warn "  Note: You may need to log out and back in for group changes to take effect"
        fi
        
        return 0
    else
        log_error "  ✗ Installation failed"
        return 1
    fi
}

install_yq() {
    log_info "  Installing yq YAML parser..."
    
    local yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
    local yq_path="/usr/local/bin/yq"
    
    sudo wget -q --show-progress "$yq_url" -O "$yq_path"
    
    if [[ $? -eq 0 ]]; then
        sudo chmod +x "$yq_path"
        log_success "  ✓ yq installed successfully"
        return 0
    else
        log_error "  ✗ Failed to download yq"
        return 1
    fi
}

get_tool_version() {
    local tool="$1"
    case "$tool" in
        yq)
            yq --version 2>&1 | head -n1 || echo ""
            ;;
        virsh)
            virsh --version 2>&1 || echo ""
            ;;
        qemu-img)
            qemu-img --version 2>&1 | head -n1 || echo ""
            ;;
        *)
            echo ""
            ;;
    esac
}

check_virtualization_support() {
    # Check for Intel VT-x or AMD-V
    if grep -qE 'vmx|svm' /proc/cpuinfo 2>/dev/null; then
        return 0
    fi
    
    # Check KVM module
    if lsmod | grep -q kvm; then
        return 0
    fi
    
    return 1
}

check_disk_space() {
    log_info "Checking available disk space..."
    
    local available_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    local required_gb=100
    
    if [[ $available_gb -lt $required_gb ]]; then
        log_warn "Low disk space: ${available_gb}GB available (recommended: ${required_gb}GB)"
        log_warn "You may encounter issues during VM creation"
    else
        log_success "✓ Sufficient disk space available: ${available_gb}GB"
    fi
}

check_network_capabilities() {
    log_info "Checking network capabilities..."
    
    # Check if user can create network bridges (requires root/sudo)
    if [[ "$(id -u)" -ne 0 ]]; then
        if ! sudo -n true 2>/dev/null; then
            log_warn "Root/sudo access may be required for network configuration"
            log_info "You may be prompted for sudo password during deployment"
        fi
    fi
    
    # Check default libvirt network
    if command -v virsh &> /dev/null; then
        if virsh net-list --all 2>/dev/null | grep -q "default"; then
            log_success "✓ Default libvirt network exists"
        else
            log_warn "Default libvirt network not found - will be created during deployment"
        fi
    fi
}

install_prerequisites() {
    log_info "Attempting to install missing prerequisites..."
    
    local os_type=""
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        os_type="$ID"
    fi
    
    case "$os_type" in
        ubuntu|debian)
            install_ubuntu_prerequisites
            ;;
        *)
            log_error "Unsupported OS: $os_type"
            log_error "This tool is designed for Ubuntu 24.04 LTS only"
            log_info "Please install prerequisites manually or use Ubuntu 24.04"
            return 1
            ;;
    esac
}

install_ubuntu_prerequisites() {
    log_info "Installing prerequisites for Ubuntu/Debian..."
    
    sudo apt-get update
    sudo apt-get install -y \
        qemu-kvm \
        libvirt-daemon-system \
        libvirt-clients \
        virtinst \
        bridge-utils \
        cpu-checker \
        virt-manager \
        iproute2 \
        jq \
        wget \
        curl \
        cloud-image-utils \
        genisoimage \
        whois
    
    # Install yq
    if ! command -v yq &> /dev/null; then
        log_info "Installing yq YAML parser..."
        sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
        sudo chmod +x /usr/local/bin/yq
    fi
    
    # Add user to libvirt group
    sudo usermod -aG libvirt "$USER"
    sudo usermod -aG kvm "$USER"
    
    # Enable and start libvirt
    sudo systemctl enable libvirtd
    sudo systemctl start libvirtd
    
    log_success "Prerequisites installed. Please log out and back in for group changes to take effect."
    
    # Download Ubuntu 24.04 image
    check_ubuntu_images
}
