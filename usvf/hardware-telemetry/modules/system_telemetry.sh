#!/bin/bash
# System Telemetry Module
# Collects motherboard, thermal, power, PCIe, USB, RAID, and BMC telemetry

collect_system_telemetry() {
    if [[ "$ENABLE_MOTHERBOARD_TELEMETRY" != "true" ]] && \
       [[ "$ENABLE_THERMAL_TELEMETRY" != "true" ]] && \
       [[ "$ENABLE_POWER_TELEMETRY" != "true" ]] && \
       [[ "$ENABLE_PCIE_TELEMETRY" != "true" ]] && \
       [[ "$ENABLE_USB_TELEMETRY" != "true" ]] && \
       [[ "$ENABLE_RAID_TELEMETRY" != "true" ]] && \
       [[ "$ENABLE_BMC_TELEMETRY" != "true" ]]; then
        return
    fi
    
    local telemetry_data=""
    local json_data="{"
    
    log_message "INFO" "Collecting System telemetry..."
    
    # === Motherboard Information ===
    if [[ "$ENABLE_MOTHERBOARD_TELEMETRY" == "true" ]] && command_exists dmidecode; then
        telemetry_data+="=== Motherboard ===\n"
        
        local mb_manufacturer=$(dmidecode -t baseboard | grep "Manufacturer:" | cut -d: -f2 | xargs)
        local mb_product=$(dmidecode -t baseboard | grep "Product Name:" | cut -d: -f2 | xargs)
        local mb_version=$(dmidecode -t baseboard | grep "Version:" | cut -d: -f2 | xargs)
        local mb_serial=$(dmidecode -t baseboard | grep "Serial Number:" | cut -d: -f2 | xargs)
        
        local bios_vendor=$(dmidecode -t bios | grep "Vendor:" | cut -d: -f2 | xargs)
        local bios_version=$(dmidecode -t bios | grep "Version:" | cut -d: -f2 | xargs)
        local bios_date=$(dmidecode -t bios | grep "Release Date:" | cut -d: -f2 | xargs)
        
        telemetry_data+="Manufacturer: $mb_manufacturer\n"
        telemetry_data+="Product: $mb_product\n"
        telemetry_data+="Version: $mb_version\n"
        telemetry_data+="Serial: $mb_serial\n"
        telemetry_data+="BIOS Vendor: $bios_vendor\n"
        telemetry_data+="BIOS Version: $bios_version\n"
        telemetry_data+="BIOS Date: $bios_date\n"
        
        json_data+="\"motherboard\": {"
        json_data+="\"manufacturer\": \"$mb_manufacturer\","
        json_data+="\"product\": \"$mb_product\","
        json_data+="\"version\": \"$mb_version\","
        json_data+="\"serial\": \"$mb_serial\","
        json_data+="\"bios_vendor\": \"$bios_vendor\","
        json_data+="\"bios_version\": \"$bios_version\","
        json_data+="\"bios_date\": \"$bios_date\""
        json_data+="},"
    fi
    
    # === Thermal Sensors ===
    if [[ "$ENABLE_THERMAL_TELEMETRY" == "true" ]]; then
        telemetry_data+="\n=== Thermal Sensors ===\n"
        json_data+="\"thermal\": {"
        
        if [[ "$THERMAL_COLLECT_ALL_SENSORS" == "true" ]]; then
            local sensor_data="["
            local sensor_count=0
            
            # Use sensors command
            if command_exists sensors; then
                local sensor_output=$(sensors 2>/dev/null)
                telemetry_data+="$sensor_output\n"
                
                # Parse critical temperatures
                while IFS= read -r line; do
                    if echo "$line" | grep -q "°C"; then
                        local sensor_name=$(echo "$line" | cut -d: -f1 | xargs)
                        local temp=$(echo "$line" | grep -oP '\+\K[0-9.]+' | head -1)
                        
                        if [[ -n "$temp" ]]; then
                            [[ $sensor_count -gt 0 ]] && sensor_data+=","
                            sensor_data+="{\"sensor\": \"$sensor_name\", \"celsius\": $temp}"
                            ((sensor_count++))
                            
                            # Check against threshold
                            if (( $(echo "$temp > $THERMAL_ALERT_THRESHOLD" | bc -l) )); then
                                telemetry_data+="WARNING: $sensor_name at ${temp}°C exceeds threshold!\n"
                            fi
                        fi
                    fi
                done <<< "$sensor_output"
            fi
            
            # Fallback to thermal zones
            if [[ $sensor_count -eq 0 ]] && [[ -d /sys/class/thermal ]]; then
                for zone in /sys/class/thermal/thermal_zone*/temp; do
                    if [[ -f "$zone" ]]; then
                        local temp=$(cat "$zone")
                        temp=$(millidegree_to_celsius "$temp")
                        local zone_type=$(cat "$(dirname "$zone")/type" 2>/dev/null || echo "unknown")
                        
                        telemetry_data+="$zone_type: ${temp}°C\n"
                        
                        [[ $sensor_count -gt 0 ]] && sensor_data+=","
                        sensor_data+="{\"type\": \"$zone_type\", \"celsius\": $temp}"
                        ((sensor_count++))
                    fi
                done
            fi
            
            sensor_data+="]"
            json_data+="\"sensors\": $sensor_data,"
            json_data+="\"count\": $sensor_count"
        fi
        
        json_data+="},"
    fi
    
    # === Power Management ===
    if [[ "$ENABLE_POWER_TELEMETRY" == "true" ]]; then
        telemetry_data+="\n=== Power Management ===\n"
        json_data+="\"power\": {"
        
        # System power consumption
        if [[ "$POWER_COLLECT_CONSUMPTION" == "true" ]]; then
            # Try RAPL
            if [[ -d /sys/class/powercap/intel-rapl ]]; then
                local total_energy=0
                for rapl in /sys/class/powercap/intel-rapl/intel-rapl:*/energy_uj; do
                    if [[ -f "$rapl" ]]; then
                        local energy=$(cat "$rapl" 2>/dev/null || echo "0")
                        total_energy=$((total_energy + energy))
                    fi
                done
                
                if [[ $total_energy -gt 0 ]]; then
                    local energy_j=$(echo "scale=3; $total_energy / 1000000" | bc)
                    telemetry_data+="Total Energy: ${energy_j}J\n"
                    json_data+="\"total_energy_joules\": $energy_j,"
                fi
            fi
        fi
        
        # PSU Status (if available via IPMI)
        if [[ "$POWER_COLLECT_PSU_STATUS" == "true" ]] && check_bmc_available; then
            local psu_status=$(ipmitool sdr type "Power Supply" 2>/dev/null)
            if [[ -n "$psu_status" ]]; then
                telemetry_data+="PSU Status:\n$psu_status\n"
                json_data+="\"psu_available\": true,"
            else
                json_data+="\"psu_available\": false,"
            fi
        fi
        
        # Battery (for systems with battery)
        if [[ "$POWER_COLLECT_BATTERY" == "true" ]] && [[ -d /sys/class/power_supply ]]; then
            for battery in /sys/class/power_supply/BAT*/; do
                if [[ -d "$battery" ]]; then
                    local capacity=$(cat "${battery}capacity" 2>/dev/null || echo "0")
                    local status=$(cat "${battery}status" 2>/dev/null || echo "Unknown")
                    
                    telemetry_data+="Battery: ${capacity}% ($status)\n"
                    json_data+="\"battery_percent\": $capacity,"
                    json_data+="\"battery_status\": \"$status\","
                    break
                fi
            done
        fi
        
        json_data="${json_data%,}}"
        json_data+="},"
    fi
    
    # === PCIe Devices ===
    if [[ "$ENABLE_PCIE_TELEMETRY" == "true" ]]; then
        telemetry_data+="\n=== PCIe Devices ===\n"
        json_data+="\"pcie\": {"
        
        local pcie_devices=$(lspci 2>/dev/null)
        local pcie_count=$(echo "$pcie_devices" | wc -l)
        
        telemetry_data+="Total PCIe Devices: $pcie_count\n"
        json_data+="\"total_devices\": $pcie_count,"
        
        if [[ "$PCIE_COLLECT_LINK_STATUS" == "true" ]]; then
            local pcie_data="["
            local dev_count=0
            
            while IFS= read -r device; do
                local bus_id=$(echo "$device" | awk '{print $1}')
                local desc=$(echo "$device" | cut -d: -f3-)
                
                # Get PCIe link info
                local link_speed=$(lspci -vv -s "$bus_id" 2>/dev/null | grep "LnkSta:" | grep -oP 'Speed \K[^,]+' | head -1)
                local link_width=$(lspci -vv -s "$bus_id" 2>/dev/null | grep "LnkSta:" | grep -oP 'Width \K[^,]+' | head -1)
                
                if [[ -n "$link_speed" ]] || [[ -n "$link_width" ]]; then
                    [[ $dev_count -gt 0 ]] && pcie_data+=","
                    pcie_data+="{\"bus_id\": \"$bus_id\", \"device\": \"$desc\", \"speed\": \"$link_speed\", \"width\": \"$link_width\"}"
                    ((dev_count++))
                fi
                
                [[ $dev_count -ge 10 ]] && break  # Limit to first 10 devices
            done <<< "$pcie_devices"
            
            pcie_data+="]"
            json_data+="\"devices\": $pcie_data"
        fi
        
        json_data+="},"
    fi
    
    # === USB Devices ===
    if [[ "$ENABLE_USB_TELEMETRY" == "true" ]]; then
        telemetry_data+="\n=== USB Devices ===\n"
        json_data+="\"usb\": {"
        
        if command_exists lsusb; then
            local usb_devices=$(lsusb 2>/dev/null)
            local usb_count=$(echo "$usb_devices" | wc -l)
            
            telemetry_data+="Total USB Devices: $usb_count\n"
            telemetry_data+="$usb_devices\n"
            
            json_data+="\"total_devices\": $usb_count"
        else
            json_data+="\"total_devices\": 0"
        fi
        
        json_data+="},"
    fi
    
    # === RAID Controllers ===
    if [[ "$ENABLE_RAID_TELEMETRY" == "true" ]]; then
        telemetry_data+="\n=== RAID Controllers ===\n"
        json_data+="\"raid\": {"
        
        local controllers=$(detect_raid_controllers)
        
        if [[ -n "$controllers" ]]; then
            local raid_data="["
            local raid_count=0
            
            while IFS= read -r controller; do
                [[ -z "$controller" ]] && continue
                
                telemetry_data+="Controller: $controller\n"
                
                case "$controller" in
                    megaraid)
                        if command_exists megacli || command_exists storcli; then
                            if [[ "$RAID_COLLECT_ARRAY_STATUS" == "true" ]]; then
                                local vd_info=$(megacli -LDInfo -Lall -aALL 2>/dev/null || storcli /call/vall show 2>/dev/null)
                                telemetry_data+="Virtual Drives:\n$vd_info\n"
                            fi
                            
                            if [[ "$RAID_COLLECT_DISK_HEALTH" == "true" ]]; then
                                local pd_info=$(megacli -PDList -aALL 2>/dev/null | grep -E "Firmware state|Inquiry Data" || storcli /call/eall/sall show 2>/dev/null | head -20)
                                telemetry_data+="Physical Drives (sample):\n$pd_info\n"
                            fi
                        fi
                        ;;
                    mdadm)
                        if command_exists mdadm; then
                            local md_stat=$(cat /proc/mdstat 2>/dev/null)
                            telemetry_data+="MD Stat:\n$md_stat\n"
                            
                            # Get detailed info for each array
                            for md in /dev/md*; do
                                [[ -b "$md" ]] || continue
                                local md_detail=$(mdadm --detail "$md" 2>/dev/null | head -20)
                                if [[ -n "$md_detail" ]]; then
                                    telemetry_data+="Array $md:\n$md_detail\n"
                                fi
                            done
                        fi
                        ;;
                esac
                
                [[ $raid_count -gt 0 ]] && raid_data+=","
                raid_data+="{\"controller\": \"$controller\"}"
                ((raid_count++))
                
            done <<< "$controllers"
            
            raid_data+="]"
            json_data+="\"controllers\": $raid_data,"
            json_data+="\"count\": $raid_count"
        else
            telemetry_data+="No RAID controllers detected\n"
            json_data+="\"controllers\": [],"
            json_data+="\"count\": 0"
        fi
        
        json_data+="},"
    fi
    
    # === BMC/IPMI ===
    if [[ "$ENABLE_BMC_TELEMETRY" == "true" ]]; then
        telemetry_data+="\n=== BMC/IPMI ===\n"
        json_data+="\"bmc\": {"
        
        if check_bmc_available; then
            # BMC Info
            local bmc_info=$(ipmitool mc info 2>/dev/null)
            telemetry_data+="BMC Info:\n$bmc_info\n"
            
            local fw_version=$(echo "$bmc_info" | grep "Firmware Revision" | cut -d: -f2 | xargs)
            json_data+="\"firmware_version\": \"$fw_version\","
            
            # Sensors
            if [[ "$BMC_COLLECT_SENSORS" == "true" ]]; then
                local sensors=$(ipmitool sdr list 2>/dev/null)
                telemetry_data+="\nSensors:\n$sensors\n"
            fi
            
            # System Event Log
            if [[ "$BMC_COLLECT_SEL" == "true" ]]; then
                local sel_count=$(ipmitool sel list 2>/dev/null | wc -l)
                telemetry_data+="SEL Entries: $sel_count\n"
                json_data+="\"sel_entries\": $sel_count,"
            fi
            
            # FRU Information
            if [[ "$BMC_COLLECT_FRU" == "true" ]]; then
                local fru=$(ipmitool fru print 2>/dev/null | head -30)
                telemetry_data+="\nFRU Info (sample):\n$fru\n"
            fi
            
            json_data+="\"available\": true"
        else
            telemetry_data+="BMC/IPMI not available\n"
            json_data+="\"available\": false"
        fi
        
        json_data+="}"
    fi
    
    # Close JSON
    json_data="${json_data%,}}"
    json_data+="}"
    
    # Log the telemetry
    log_telemetry "System" "$telemetry_data"
    
    # Add to JSON output
    json_add_module "system" "$json_data"
    
    log_message "INFO" "System telemetry collection complete"
}

export -f collect_system_telemetry
