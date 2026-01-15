#!/bin/bash

###############################################################################
# Mellanox Network Interface Detection Script
# 
# Detects Mellanox network interfaces and saves them to configuration file
# This script is embedded in cloud-init user-data and executed on first boot
###############################################################################

set -e

CONFIG_DIR="/etc/frr-bgp-config"
OUTPUT_FILE="${CONFIG_DIR}/mellanox-interfaces.conf"
LOG_FILE="/var/log/mellanox-detect.log"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "Starting Mellanox interface detection..."

# Clear previous configuration
> "$OUTPUT_FILE"

# Detect Mellanox interfaces
MELLANOX_COUNT=0

for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    
    # Skip loopback and virtual interfaces
    if [[ "$iface_name" == "lo" ]] || [[ "$iface_name" =~ ^(docker|br-|veth|virbr) ]]; then
        continue
    fi
    
    # Check if interface has a device directory (physical interface)
    if [[ ! -d "$iface/device" ]]; then
        continue
    fi
    
    # Read vendor ID
    if [[ -f "$iface/device/vendor" ]]; then
        vendor_id=$(cat "$iface/device/vendor" 2>/dev/null || echo "")
        
        # Check for Mellanox vendor ID (0x15b3)
        if [[ "$vendor_id" == "0x15b3" ]]; then
            log "Found Mellanox interface: $iface_name (Vendor: $vendor_id)"
            echo "$iface_name" >> "$OUTPUT_FILE"
            ((MELLANOX_COUNT++))
        fi
    fi
done

if [[ $MELLANOX_COUNT -eq 0 ]]; then
    log "WARNING: No Mellanox interfaces detected!"
    log "BGP configuration will not be applied."
    exit 0
else
    log "Detected $MELLANOX_COUNT Mellanox interface(s)"
    log "Interface list saved to: $OUTPUT_FILE"
    cat "$OUTPUT_FILE" | while read iface; do
        log "  - $iface"
    done
fi

log "Mellanox detection complete"
