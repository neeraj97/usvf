#!/bin/bash
# Dependency Installation Module

install_dependencies() {
    local REQUIRED_PKGS="stress-ng fio iperf3 ipmitool lshw dmidecode nvme-cli smartmontools ethtool pciutils sysstat sysbench hdparm lm-sensors edac-utils jq bc iperf wget curl"
    
    echo "[→] Updating package repositories..."
    apt-get update -qq 2>&1 | tee "$OUTPUT_DIR/logs/apt-update.log" > /dev/null
    
    echo "[→] Installing required packages..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y $REQUIRED_PKGS 2>&1 | tee "$OUTPUT_DIR/logs/apt-install.log" > /dev/null
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Failed to install dependencies. Check logs.${NC}"
        exit 1
    fi
    
    # Initialize sensors
    echo "[→] Initializing sensor monitoring..."
    sensors-detect --auto 2>&1 | tee "$OUTPUT_DIR/logs/sensors-detect.log" > /dev/null || true
    
    echo -e "${GREEN}[✓] All dependencies installed${NC}"
}
