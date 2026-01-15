#!/bin/bash

###############################################################################
# Package Installation Module
# Installs packages into extracted filesystem
###############################################################################

install_packages() {
    local work_dir="$1"
    local additional_packages="$2"
    
    local squashfs_extract="${work_dir}/squashfs_extract"
    
    # Prepare chroot environment
    echo "  - Preparing chroot environment..."
    mount --bind /dev "${squashfs_extract}/dev"
    mount --bind /run "${squashfs_extract}/run"
    mount -t proc none "${squashfs_extract}/proc"
    mount -t sysfs none "${squashfs_extract}/sys"
    mount -t devpts none "${squashfs_extract}/dev/pts"
    
    # Copy DNS configuration
    cp /etc/resolv.conf "${squashfs_extract}/etc/resolv.conf"
    
    # Define package lists
    local base_packages=(
        # Network tools
        net-tools
        iproute2
        ethtool
        iperf3
        
        # FRR for BGP
        frr
        frr-pythontools
        
        # Debugging tools
        tcpdump
        tshark
        strace
        sysstat
        htop
        iotop
        lsof
        netcat-openbsd
        traceroute
        curl
        wget
        vim
        nano
        dnsutils
        iputils-ping
        
    )
    
    # Update package lists in chroot
    echo "  - Updating package lists..."
    chroot "$squashfs_extract" /bin/bash -c "apt-get update -qq"
    
    # Install base packages
    echo "  - Installing base packages..."
    chroot "$squashfs_extract" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y ${base_packages[*]}"
    
    # Install additional packages if specified
    if [[ -n "$additional_packages" ]]; then
        echo "  - Installing additional packages: $additional_packages"
        # Convert comma-separated list to space-separated
        local pkg_list="${additional_packages//,/ }"
        chroot "$squashfs_extract" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y $pkg_list"
    fi
    
    # Enable FRR daemons
    echo "  - Configuring FRR..."
    chroot "$squashfs_extract" /bin/bash -c "sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons"
    chroot "$squashfs_extract" /bin/bash -c "sed -i 's/^zebra=no/zebra=yes/' /etc/frr/daemons"
    
    # Enable services
    echo "  - Enabling services..."
    chroot "$squashfs_extract" /bin/bash -c "systemctl enable frr" 2>/dev/null || true
    
    # Clean up
    echo "  - Cleaning up package cache..."
    chroot "$squashfs_extract" /bin/bash -c "apt-get clean"
    chroot "$squashfs_extract" /bin/bash -c "rm -rf /var/lib/apt/lists/*"
    
    # Unmount chroot filesystems
    echo "  - Unmounting chroot filesystems..."
    umount "${squashfs_extract}/dev/pts" 2>/dev/null || true
    umount "${squashfs_extract}/sys" 2>/dev/null || true
    umount "${squashfs_extract}/proc" 2>/dev/null || true
    umount "${squashfs_extract}/run" 2>/dev/null || true
    umount "${squashfs_extract}/dev" 2>/dev/null || true
    
    echo "  - Package installation completed"
    return 0
}
