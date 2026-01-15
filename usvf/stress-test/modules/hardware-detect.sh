#!/bin/bash
# Hardware Detection Module

detect_hardware() {
    local HW_REPORT="$OUTPUT_DIR/reports/hardware_inventory.txt"
    
    echo "Starting hardware discovery..." | tee "$HW_REPORT"
    echo "================================" | tee -a "$HW_REPORT"
    echo "" | tee -a "$HW_REPORT"
    
    # --- CPU Detection ---
    echo "[→] Detecting CPU..." | tee -a "$HW_REPORT"
    lscpu > "$OUTPUT_DIR/raw_data/lscpu.txt"
    lscpu -J > "$OUTPUT_DIR/raw_data/lscpu.json"
    
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    CPU_CORES=$(nproc)
    CPU_THREADS=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
    CPU_SOCKETS=$(lscpu | grep "Socket(s):" | awk '{print $2}')
    
    echo "CPU Information:" | tee -a "$HW_REPORT"
    echo "  Model: $CPU_MODEL" | tee -a "$HW_REPORT"
    echo "  Sockets: $CPU_SOCKETS" | tee -a "$HW_REPORT"
    echo "  Total Cores: $CPU_CORES" | tee -a "$HW_REPORT"
    echo "  Total Threads: $CPU_THREADS" | tee -a "$HW_REPORT"
    echo "" | tee -a "$HW_REPORT"
    
    # Export for other modules
    export CPU_MODEL CPU_CORES CPU_THREADS CPU_SOCKETS
    
    # --- Memory Detection ---
    echo "[→] Detecting Memory..." | tee -a "$HW_REPORT"
    dmidecode -t memory > "$OUTPUT_DIR/raw_data/dmidecode_memory.txt"
    
    TOTAL_MEM_GB=$(free -g | awk '/^Mem:/ {print $2}')
    MEM_SPEED=$(dmidecode -t memory | grep "Speed:" | grep -v "Unknown" | head -1 | awk '{print $2, $3}')
    MEM_TYPE=$(dmidecode -t memory | grep "Type:" | grep -v "Type Detail" | grep -v "Error Correction" | head -1 | awk '{print $2}')
    DIMM_COUNT=$(dmidecode -t memory | grep "Size:" | grep -v "No Module Installed" | wc -l)
    
    echo "Memory Information:" | tee -a "$HW_REPORT"
    echo "  Total Memory: ${TOTAL_MEM_GB} GB" | tee -a "$HW_REPORT"
    echo "  Type: $MEM_TYPE" | tee -a "$HW_REPORT"
    echo "  Speed: $MEM_SPEED" | tee -a "$HW_REPORT"
    echo "  Populated DIMMs: $DIMM_COUNT" | tee -a "$HW_REPORT"
    echo "" | tee -a "$HW_REPORT"
    
    export TOTAL_MEM_GB MEM_SPEED MEM_TYPE DIMM_COUNT
    
    # --- Storage Detection ---
    echo "[→] Detecting Storage Devices..." | tee -a "$HW_REPORT"
    lsblk -o NAME,SIZE,TYPE,ROTA,MODEL,TRAN > "$OUTPUT_DIR/raw_data/lsblk.txt"
    lsblk -J -o NAME,SIZE,TYPE,ROTA,MODEL,TRAN,SERIAL > "$OUTPUT_DIR/raw_data/lsblk.json"
    
    # Detect NVMe devices
    echo "Storage Devices:" | tee -a "$HW_REPORT"
    NVME_DEVICES=$(nvme list 2>/dev/null | grep "^/dev/nvme" | awk '{print $1}' || echo "")
    if [[ -n "$NVME_DEVICES" ]]; then
        echo "" | tee -a "$HW_REPORT"
        echo "  NVMe Devices:" | tee -a "$HW_REPORT"
        while IFS= read -r nvme_dev; do
            NVME_MODEL=$(nvme id-ctrl "$nvme_dev" 2>/dev/null | grep "^mn" | cut -d: -f2 | xargs || echo "Unknown")
            NVME_SIZE=$(lsblk -n -o SIZE "$nvme_dev" 2>/dev/null | head -1 || echo "Unknown")
            NVME_SERIAL=$(nvme id-ctrl "$nvme_dev" 2>/dev/null | grep "^sn" | cut -d: -f2 | xargs || echo "Unknown")
            echo "    - Device: $nvme_dev" | tee -a "$HW_REPORT"
            echo "      Model: $NVME_MODEL" | tee -a "$HW_REPORT"
            echo "      Size: $NVME_SIZE" | tee -a "$HW_REPORT"
            echo "      Serial: $NVME_SERIAL" | tee -a "$HW_REPORT"
            
            # Save to JSON for later processing
            echo "$nvme_dev|$NVME_MODEL|$NVME_SIZE|NVMe|$NVME_SERIAL" >> "$OUTPUT_DIR/raw_data/storage_devices.txt"
        done <<< "$NVME_DEVICES"
    fi
    
    # Detect SATA/SAS SSDs and HDDs
    BLOCK_DEVICES=$(lsblk -d -n -o NAME,ROTA,TYPE | grep "disk" | awk '{print $1,$2}')
    if [[ -n "$BLOCK_DEVICES" ]]; then
        echo "" | tee -a "$HW_REPORT"
        echo "  SATA/SAS Devices:" | tee -a "$HW_REPORT"
        while IFS= read -r line; do
            DEV_NAME=$(echo "$line" | awk '{print $1}')
            IS_ROTA=$(echo "$line" | awk '{print $2}')
            
            # Skip if it's an NVMe device (already processed)
            [[ "$DEV_NAME" == nvme* ]] && continue
            
            DEV_PATH="/dev/$DEV_NAME"
            DEV_MODEL=$(lsblk -n -o MODEL "$DEV_PATH" 2>/dev/null | xargs || echo "Unknown")
            DEV_SIZE=$(lsblk -n -o SIZE "$DEV_PATH" 2>/dev/null | head -1 || echo "Unknown")
            DEV_SERIAL=$(smartctl -i "$DEV_PATH" 2>/dev/null | grep "Serial Number" | cut -d: -f2 | xargs || echo "Unknown")
            
            if [[ "$IS_ROTA" == "0" ]]; then
                DEV_TYPE="SSD"
            else
                DEV_TYPE="HDD"
            fi
            
            echo "    - Device: $DEV_PATH ($DEV_TYPE)" | tee -a "$HW_REPORT"
            echo "      Model: $DEV_MODEL" | tee -a "$HW_REPORT"
            echo "      Size: $DEV_SIZE" | tee -a "$HW_REPORT"
            echo "      Serial: $DEV_SERIAL" | tee -a "$HW_REPORT"
            
            # Save to file for later processing
            echo "$DEV_PATH|$DEV_MODEL|$DEV_SIZE|$DEV_TYPE|$DEV_SERIAL" >> "$OUTPUT_DIR/raw_data/storage_devices.txt"
        done <<< "$BLOCK_DEVICES"
    fi
    echo "" | tee -a "$HW_REPORT"
    
    # --- Network Interface Detection ---
    echo "[→] Detecting Network Interfaces..." | tee -a "$HW_REPORT"
    ip -j link show > "$OUTPUT_DIR/raw_data/network_interfaces.json"
    
    echo "Network Interfaces:" | tee -a "$HW_REPORT"
    NETWORK_DEVS=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo")
    
    while IFS= read -r iface; do
        [[ -z "$iface" ]] && continue
        
        # Get interface details
        IFACE_STATE=$(ip link show "$iface" | grep -o "state [A-Z]*" | awk '{print $2}')
        IFACE_MAC=$(ip link show "$iface" | grep -o "link/ether [0-9a-f:]*" | awk '{print $2}')
        
        # Try to get driver and firmware info
        IFACE_DRIVER=$(ethtool -i "$iface" 2>/dev/null | grep "^driver:" | awk '{print $2}' || echo "Unknown")
        IFACE_VERSION=$(ethtool -i "$iface" 2>/dev/null | grep "^version:" | awk '{print $2}' || echo "Unknown")
        IFACE_FIRMWARE=$(ethtool -i "$iface" 2>/dev/null | grep "^firmware-version:" | awk '{print $2}' || echo "Unknown")
        
        # Get speed if available
        IFACE_SPEED=$(ethtool "$iface" 2>/dev/null | grep "Speed:" | awk '{print $2}' || echo "Unknown")
        
        # Check if it's a Mellanox or other smart NIC
        IFACE_BUS=$(ethtool -i "$iface" 2>/dev/null | grep "^bus-info:" | awk '{print $2}' || echo "Unknown")
        NIC_DETAILS=""
        if [[ "$IFACE_BUS" != "Unknown" ]]; then
            NIC_DETAILS=$(lspci -s "$IFACE_BUS" 2>/dev/null | cut -d: -f3- || echo "")
        fi
        
        echo "  - Interface: $iface" | tee -a "$HW_REPORT"
        echo "    State: $IFACE_STATE" | tee -a "$HW_REPORT"
        echo "    MAC: $IFACE_MAC" | tee -a "$HW_REPORT"
        echo "    Driver: $IFACE_DRIVER" | tee -a "$HW_REPORT"
        echo "    Speed: $IFACE_SPEED" | tee -a "$HW_REPORT"
        [[ -n "$NIC_DETAILS" ]] && echo "    Hardware: $NIC_DETAILS" | tee -a "$HW_REPORT"
        echo "    Firmware: $IFACE_FIRMWARE" | tee -a "$HW_REPORT"
        
        # Save to file for network testing
        echo "$iface|$IFACE_STATE|$IFACE_SPEED|$IFACE_DRIVER|$NIC_DETAILS" >> "$OUTPUT_DIR/raw_data/network_devices.txt"
    done <<< "$NETWORK_DEVS"
    echo "" | tee -a "$HW_REPORT"
    
    # --- PCI Device Detection ---
    echo "[→] Detecting PCI Devices..." | tee -a "$HW_REPORT"
    lspci -vv > "$OUTPUT_DIR/raw_data/lspci_verbose.txt"
    lspci -nn > "$OUTPUT_DIR/raw_data/lspci.txt"
    
    # Look for special devices (GPUs, Accelerators, RAID controllers, etc.)
    echo "Special PCI Devices:" | tee -a "$HW_REPORT"
    
    # GPUs
    GPU_DEVICES=$(lspci | grep -i "vga\|3d\|display" || echo "")
    if [[ -n "$GPU_DEVICES" ]]; then
        echo "  GPUs/Display Adapters:" | tee -a "$HW_REPORT"
        while IFS= read -r gpu; do
            [[ -z "$gpu" ]] && continue
            echo "    - $gpu" | tee -a "$HW_REPORT"
        done <<< "$GPU_DEVICES"
    fi
    
    # RAID Controllers
    RAID_DEVICES=$(lspci | grep -i "raid\|megaraid\|adaptec" || echo "")
    if [[ -n "$RAID_DEVICES" ]]; then
        echo "  RAID Controllers:" | tee -a "$HW_REPORT"
        while IFS= read -r raid; do
            [[ -z "$raid" ]] && continue
            echo "    - $raid" | tee -a "$HW_REPORT"
        done <<< "$RAID_DEVICES"
    fi
    
    # Infiniband/RDMA
    IB_DEVICES=$(lspci | grep -i "infiniband\|mellanox" || echo "")
    if [[ -n "$IB_DEVICES" ]]; then
        echo "  InfiniBand/RDMA Devices:" | tee -a "$HW_REPORT"
        while IFS= read -r ib; do
            [[ -z "$ib" ]] && continue
            echo "    - $ib" | tee -a "$HW_REPORT"
        done <<< "$IB_DEVICES"
    fi
    
    # Unknown/Other PCI devices
    echo "  Other PCI Devices:" | tee -a "$HW_REPORT"
    lspci | grep -v -i "vga\|3d\|display\|raid\|infiniband\|mellanox\|bridge\|isa\|host\|ethernet\|network" | head -20 | while IFS= read -r device; do
        [[ -z "$device" ]] && continue
        echo "    - $device" | tee -a "$HW_REPORT"
        # Save unknown devices for interactive testing later
        echo "$device" >> "$OUTPUT_DIR/raw_data/unknown_pci_devices.txt"
    done
    echo "" | tee -a "$HW_REPORT"
    
    # --- BMC/IPMI Detection ---
    echo "[→] Detecting BMC/IPMI..." | tee -a "$HW_REPORT"
    BMC_INFO=$(ipmitool mc info 2>/dev/null || echo "")
    if [[ -n "$BMC_INFO" ]]; then
        echo "BMC Information:" | tee -a "$HW_REPORT"
        echo "$BMC_INFO" | grep -E "Manufacturer|Product|Firmware" | tee -a "$HW_REPORT"
        echo "" | tee -a "$HW_REPORT"
        export BMC_AVAILABLE="yes"
    else
        echo "BMC/IPMI: Not available or not accessible" | tee -a "$HW_REPORT"
        echo "" | tee -a "$HW_REPORT"
        export BMC_AVAILABLE="no"
    fi
    
    echo "Hardware discovery complete!" | tee -a "$HW_REPORT"
}
