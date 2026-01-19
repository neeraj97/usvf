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
    
    local missing_tools=()
    local virtualization_ok=true
    
    # Check operating system
    if [[ "$(uname)" != "Linux" ]] && [[ "$(uname)" != "Darwin" ]]; then
        log_error "Unsupported operating system: $(uname)"
        log_error "This tool requires Linux or macOS"
        return 1
    fi
    
    # Check if running on macOS
    if [[ "$(uname)" == "Darwin" ]]; then
        log_warn "Running on macOS - some features may require additional setup"
    fi
    
    # Check for required tools
    check_tool "yq" "YAML parser" "brew install yq" missing_tools
    check_tool "jq" "JSON processor" "brew install jq" missing_tools
    check_tool "virsh" "KVM management" "Install libvirt: brew install libvirt (macOS) or apt install libvirt-clients (Ubuntu)" missing_tools
    check_tool "virt-install" "VM installation" "Install virt-install: brew install virt-manager (macOS) or apt install virtinst (Ubuntu)" missing_tools
    check_tool "qemu-img" "Disk image management" "Install QEMU: brew install qemu (macOS) or apt install qemu-utils (Ubuntu)" missing_tools
    check_tool "wget" "File download" "Install wget: brew install wget (macOS) or apt install wget (Ubuntu)" missing_tools
    check_tool "curl" "File download" "Install curl: brew install curl (macOS) or apt install curl (Ubuntu)" missing_tools
    
    # Network tools
    check_tool "ip" "Network configuration" "Install iproute2: brew install iproute2mac (macOS) or apt install iproute2 (Ubuntu)" missing_tools
    
    # Check for SSH
    check_tool "ssh" "SSH client" "Install OpenSSH: brew install openssh" missing_tools
    check_tool "ssh-keygen" "SSH key generation" "Install OpenSSH: brew install openssh" missing_tools
    
    # Check virtualization support (Linux only)
    if [[ "$(uname)" == "Linux" ]]; then
        if ! check_virtualization_support; then
            virtualization_ok=false
            log_error "Hardware virtualization is not enabled or not supported"
            log_error "Please enable VT-x/AMD-V in BIOS settings"
        else
            log_success "✓ Hardware virtualization is enabled"
        fi
    fi
    
    # Check libvirt daemon
    if command -v virsh &> /dev/null; then
        if ! virsh list &> /dev/null; then
            log_warn "libvirt daemon is not running or not accessible"
            log_info "Try starting it: sudo systemctl start libvirtd (Linux) or brew services start libvirt (macOS)"
        else
            log_success "✓ libvirt daemon is running"
        fi
    fi
    
    # Report missing tools
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools:"
        for tool_info in "${missing_tools[@]}"; do
            log_error "  - $tool_info"
        done
        return 1
    fi
    
    if [[ "$virtualization_ok" == "false" ]]; then
        return 1
    fi
    
    # Check disk space
    check_disk_space
    
    # Check network capabilities
    check_network_capabilities
    
    # Check and download Ubuntu 24.04 images
    check_ubuntu_images
    
    log_success "✓ All prerequisites are met"
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
        if [[ "$(uname)" == "Darwin" ]]; then
            local image_age=$(( ($(date +%s) - $(stat -f %m "$ubuntu_image")) / 86400 ))
        else
            local image_age=$(( ($(date +%s) - $(stat -c %Y "$ubuntu_image")) / 86400 ))
        fi
        
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

check_tool() {
    local tool_name="$1"
    local tool_desc="$2"
    local install_cmd="$3"
    local -n missing_ref=$4
    
    if command -v "$tool_name" &> /dev/null; then
        local version=$(get_tool_version "$tool_name")
        log_success "✓ $tool_desc ($tool_name) is installed $version"
        return 0
    else
        log_warn "✗ $tool_desc ($tool_name) is not installed"
        missing_ref+=("$tool_desc ($tool_name) - Install: $install_cmd")
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
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS - assume virtualization is available
        return 0
    fi
    
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
    
    local available_gb
    if [[ "$(uname)" == "Darwin" ]]; then
        available_gb=$(df -g / | awk 'NR==2 {print $4}')
    else
        available_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    fi
    
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
    elif [[ "$(uname)" == "Darwin" ]]; then
        os_type="macos"
    fi
    
    case "$os_type" in
        ubuntu|debian)
            install_ubuntu_prerequisites
            ;;
        centos|rhel|fedora)
            install_rhel_prerequisites
            ;;
        macos)
            install_macos_prerequisites
            ;;
        *)
            log_error "Unsupported OS for automatic installation: $os_type"
            log_info "Please install prerequisites manually"
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

install_rhel_prerequisites() {
    log_info "Installing prerequisites for RHEL/CentOS/Fedora..."
    
    sudo dnf install -y \
        qemu-kvm \
        libvirt \
        virt-install \
        bridge-utils \
        virt-manager \
        iproute \
        jq \
        wget \
        curl \
        cloud-utils \
        genisoimage
    
    # Install yq
    if ! command -v yq &> /dev/null; then
        log_info "Installing yq YAML parser..."
        sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
        sudo chmod +x /usr/local/bin/yq
    fi
    
    # Add user to libvirt group
    sudo usermod -aG libvirt "$USER"
    
    # Enable and start libvirt
    sudo systemctl enable libvirtd
    sudo systemctl start libvirtd
    
    log_success "Prerequisites installed. Please log out and back in for group changes to take effect."
    
    # Download Ubuntu 24.04 image
    check_ubuntu_images
}

install_macos_prerequisites() {
    log_info "Installing prerequisites for macOS..."
    
    if ! command -v brew &> /dev/null; then
        log_error "Homebrew is not installed. Please install it first:"
        log_error "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        return 1
    fi
    
    brew install qemu libvirt virt-manager yq jq iproute2mac wget curl cdrtools
    
    # Start libvirt
    brew services start libvirt
    
    log_success "Prerequisites installed for macOS"
    
    # Download Ubuntu 24.04 image
    check_ubuntu_images
}
