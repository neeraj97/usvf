#!/bin/bash

###############################################################################
# Mellanox Detection Module
# Detects Mellanox network interfaces and prepares detection script
###############################################################################

prepare_mellanox_detection() {
    local work_dir="$1"
    local squashfs_extract="${work_dir}/squashfs_extract"
    
    # Create detection script that will run on first boot
    echo "  - Creating Mellanox interface detection script..."
    
    cat > "${squashfs_extract}/usr/local/bin/detect-mellanox-interfaces.sh" << 'EOF'
#!/bin/bash

###############################################################################
# Mellanox Interface Detection Script
# Runs at first boot to detect and list Mellanox interfaces
###############################################################################

MELLANOX_IFACES_FILE="/etc/mellanox-interfaces.conf"

detect_mellanox_interfaces() {
    local ifaces=()
    
    # Method 1: Check by PCI vendor ID (Mellanox/NVIDIA = 15b3)
    for net_dev in /sys/class/net/*; do
        if [[ -L "$net_dev/device" ]]; then
            local vendor=$(cat "$net_dev/device/vendor" 2>/dev/null)
            if [[ "$vendor" == "0x15b3" ]]; then
                local iface=$(basename "$net_dev")
                ifaces+=("$iface")
            fi
        fi
    done
    
    # Method 2: Check using lspci for Mellanox devices
    if command -v lspci &> /dev/null; then
        while IFS= read -r line; do
            # Extract interface name from network device
            local pci_addr=$(echo "$line" | awk '{print $1}')
            for net_dev in /sys/class/net/*; do
                if [[ -L "$net_dev/device" ]]; then
                    local dev_pci=$(basename $(readlink "$net_dev/device"))
                    if [[ "$dev_pci" == *"$pci_addr"* ]]; then
                        local iface=$(basename "$net_dev")
                        # Add if not already in list
                        if [[ ! " ${ifaces[@]} " =~ " ${iface} " ]]; then
                            ifaces+=("$iface")
                        fi
                    fi
                fi
            done
        done < <(lspci | grep -i mellanox | grep -i ethernet)
    fi
    
    # Write to file
    > "$MELLANOX_IFACES_FILE"
    for iface in "${ifaces[@]}"; do
        echo "$iface" >> "$MELLANOX_IFACES_FILE"
    done
    
    echo "Detected ${#ifaces[@]} Mellanox interface(s): ${ifaces[*]}"
    
    return 0
}

# Main execution
detect_mellanox_interfaces
EOF
    
    chmod +x "${squashfs_extract}/usr/local/bin/detect-mellanox-interfaces.sh"
    
    # Create systemd service to run detection on first boot
    echo "  - Creating systemd service for Mellanox detection..."
    
    cat > "${squashfs_extract}/etc/systemd/system/mellanox-detect.service" << 'EOF'
[Unit]
Description=Detect Mellanox Network Interfaces
After=network-pre.target
Before=network.target frr.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/detect-mellanox-interfaces.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable the service in chroot
    chroot "$squashfs_extract" /bin/bash -c "systemctl enable mellanox-detect.service" 2>/dev/null || true
    
    echo "  - Mellanox detection prepared"
    return 0
}
