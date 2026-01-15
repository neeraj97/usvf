#!/bin/bash
# Storage Telemetry Module
# Collects comprehensive storage metrics including SMART data, temperature, wear level, TRIM status, I/O statistics

collect_storage_telemetry() {
    if [[ "$ENABLE_STORAGE_TELEMETRY" != "true" ]]; then
        return
    fi
    
    local telemetry_data=""
    local json_data="{"
    
    log_message "INFO" "Collecting Storage telemetry..."
    
    # Get all storage devices
    local devices=$(detect_storage_devices)
    
    if [[ -z "$devices" ]]; then
        telemetry_data+="No storage devices detected\n"
        json_data+="\"devices\": []}"
        log_telemetry "Storage" "$telemetry_data"
        json_add_module "storage" "$json_data"
        return
    fi
    
    json_data+="\"devices\": ["
    local device_count=0
    
    while IFS='|' read -r device type; do
        [[ -z "$device" ]] && continue
        
        [[ $device_count -gt 0 ]] && json_data+=","
        
        telemetry_data+="\n=== Device: $device ($type) ===\n"
        json_data+="{\"device\": \"$device\", \"type\": \"$type\","
        
        # === Basic Device Information ===
        local model=$(lsblk -n -o MODEL "$device" 2>/dev/null | xargs || echo "Unknown")
        local size=$(lsblk -n -o SIZE "$device" 2>/dev/null | head -1 || echo "Unknown")
        local serial=""
        
        if [[ "$type" == "nvme" ]]; then
            serial=$(nvme id-ctrl "$device" 2>/dev/null | grep "^sn" | awk '{print $3}' || echo "Unknown")
        else
            serial=$(smartctl -i "$device" 2>/dev/null | grep "Serial Number" | awk '{print $3}' || echo "Unknown")
        fi
        
        telemetry_data+="Model: $model\n"
        telemetry_data+="Size: $size\n"
        telemetry_data+="Serial: $serial\n"
        
        json_data+="\"model\": \"$model\","
        json_data+="\"size\": \"$size\","
        json_data+="\"serial\": \"$serial\","
        
        # === SMART Data ===
        if [[ "$STORAGE_COLLECT_SMART" == "true" ]] && command_exists smartctl; then
            telemetry_data+="\n--- SMART Status ---\n"
            
            local smart_output
            if [[ "$type" == "nvme" ]]; then
                smart_output=$(smartctl -A "$device" 2>/dev/null)
            else
                smart_output=$(smartctl -A "$device" 2>/dev/null)
            fi
            
            # Overall SMART health
            local health_status=$(smartctl -H "$device" 2>/dev/null | grep "SMART overall-health" | awk '{print $NF}')
            telemetry_data+="Health Status: $health_status\n"
            json_data+="\"smart_health\": \"$health_status\","
            
            # Power On Hours
            local power_on_hours=$(echo "$smart_output" | grep -i "Power_On_Hours\|Power On Hours" | awk '{print $(NF-1)}' | head -1)
            if [[ -n "$power_on_hours" ]]; then
                telemetry_data+="Power On Hours: $power_on_hours\n"
                json_data+="\"power_on_hours\": $power_on_hours,"
            fi
            
            # Read/Write Statistics
            local data_units_read=$(echo "$smart_output" | grep -i "Data Units Read" | awk '{print $(NF-1)}')
            local data_units_written=$(echo "$smart_output" | grep -i "Data Units Written" | awk '{print $(NF-1)}')
            
            if [[ -n "$data_units_read" ]]; then
                telemetry_data+="Data Units Read: $data_units_read\n"
                json_data+="\"data_units_read\": $data_units_read,"
            fi
            
            if [[ -n "$data_units_written" ]]; then
                telemetry_data+="Data Units Written: $data_units_written\n"
                json_data+="\"data_units_written\": $data_units_written,"
            fi
            
            json_data+="\"smart_available\": true,"
        else
            json_data+="\"smart_available\": false,"
        fi
        
        # === Temperature ===
        if [[ "$STORAGE_COLLECT_TEMPERATURE" == "true" ]]; then
            telemetry_data+="\n--- Temperature ---\n"
            
            local temp=""
            if [[ "$type" == "nvme" ]] && command_exists nvme; then
                # NVMe temperature
                temp=$(nvme smart-log "$device" 2>/dev/null | grep "temperature" | awk '{print $3}')
                if [[ -n "$temp" ]]; then
                    telemetry_data+="Temperature: ${temp}°C\n"
                    json_data+="\"temperature_celsius\": $temp,"
                    
                    # Check critical temperature
                    local critical_temp=$(nvme smart-log "$device" 2>/dev/null | grep "critical_temp_time" | awk '{print $3}')
                    if [[ -n "$critical_temp" ]] && [[ "$critical_temp" != "0" ]]; then
                        telemetry_data+="WARNING: Critical temperature threshold reached!\n"
                    fi
                fi
            elif command_exists smartctl; then
                # SATA/SAS temperature
                temp=$(smartctl -A "$device" 2>/dev/null | grep -i "Temperature_Celsius\|Temperature" | awk '{print $(NF-1)}' | head -1)
                if [[ -n "$temp" ]]; then
                    telemetry_data+="Temperature: ${temp}°C\n"
                    json_data+="\"temperature_celsius\": $temp,"
                fi
            fi
            
            if [[ -z "$temp" ]]; then
                telemetry_data+="Temperature: Not available\n"
                json_data+="\"temperature_celsius\": null,"
            fi
        fi
        
        # === Wear Level (SSD specific) ===
        if [[ "$STORAGE_COLLECT_WEAR_LEVEL" == "true" ]] && [[ "$type" != "hdd" ]]; then
            telemetry_data+="\n--- Wear Level ---\n"
            
            local wear_level=""
            local remaining_life=""
            
            if [[ "$type" == "nvme" ]] && command_exists nvme; then
                # NVMe wear level
                remaining_life=$(nvme smart-log "$device" 2>/dev/null | grep "available_spare " | awk '{print $3}' | tr -d '%')
                local used_endurance=$(nvme smart-log "$device" 2>/dev/null | grep "percentage_used" | awk '{print $3}' | tr -d '%')
                
                if [[ -n "$remaining_life" ]]; then
                    telemetry_data+="Available Spare: ${remaining_life}%\n"
                    json_data+="\"available_spare_percent\": $remaining_life,"
                fi
                
                if [[ -n "$used_endurance" ]]; then
                    telemetry_data+="Percentage Used: ${used_endurance}%\n"
                    json_data+="\"endurance_used_percent\": $used_endurance,"
                    
                    # Calculate remaining percentage
                    remaining_life=$((100 - used_endurance))
                fi
            elif command_exists smartctl; then
                # SATA SSD wear level
                wear_level=$(smartctl -A "$device" 2>/dev/null | grep -i "Wear_Leveling_Count\|Media_Wearout_Indicator" | awk '{print $(NF-1)}' | head -1)
                remaining_life=$(smartctl -A "$device" 2>/dev/null | grep -i "Remaining_Lifetime_Perc" | awk '{print $(NF-1)}' | head -1)
                
                if [[ -n "$wear_level" ]]; then
                    telemetry_data+="Wear Leveling Count: $wear_level\n"
                    json_data+="\"wear_level\": $wear_level,"
                fi
                
                if [[ -n "$remaining_life" ]]; then
                    telemetry_data+="Remaining Life: ${remaining_life}%\n"
                    json_data+="\"remaining_life_percent\": $remaining_life,"
                fi
            fi
            
            # Alert on low remaining life
            if [[ -n "$remaining_life" ]] && [[ "$remaining_life" -lt "$ALERT_STORAGE_WEAR_WARNING" ]]; then
                if [[ "$remaining_life" -lt "$ALERT_STORAGE_WEAR_CRITICAL" ]]; then
                    telemetry_data+="CRITICAL: Remaining life below ${ALERT_STORAGE_WEAR_CRITICAL}%!\n"
                else
                    telemetry_data+="WARNING: Remaining life below ${ALERT_STORAGE_WEAR_WARNING}%!\n"
                fi
            fi
        fi
        
        # === TRIM Status (SSD specific) ===
        if [[ "$STORAGE_COLLECT_TRIM_STATUS" == "true" ]] && [[ "$type" != "hdd" ]]; then
            telemetry_data+="\n--- TRIM Status ---\n"
            
            # Check if TRIM is supported
            local trim_supported="unknown"
            
            if [[ "$type" == "nvme" ]]; then
                # NVMe always supports TRIM (called Deallocate)
                trim_supported="yes"
                telemetry_data+="TRIM/Deallocate: Supported\n"
            else
                # Check SATA SSD TRIM support
                local trim_check=$(hdparm -I "$device" 2>/dev/null | grep -i "TRIM supported")
                if [[ -n "$trim_check" ]]; then
                    trim_supported="yes"
                    telemetry_data+="TRIM: Supported\n"
                else
                    trim_supported="no"
                    telemetry_data+="TRIM: Not supported\n"
                fi
            fi
            
            json_data+="\"trim_supported\": \"$trim_supported\","
            
            # Check filesystem mount options for TRIM
            local mount_point=$(lsblk -n -o MOUNTPOINT "$device" 2>/dev/null | grep -v "^$" | head -1)
            if [[ -n "$mount_point" ]]; then
                local mount_opts=$(mount | grep "$device" | awk '{print $6}')
                if echo "$mount_opts" | grep -q "discard"; then
                    telemetry_data+="Continuous TRIM: Enabled\n"
                    json_data+="\"trim_enabled\": true,"
                else
                    telemetry_data+="Continuous TRIM: Disabled (consider periodic fstrim)\n"
                    json_data+="\"trim_enabled\": false,"
                    
                    # Check when last fstrim was run
                    if command_exists fstrim; then
                        telemetry_data+="Recommendation: Run 'fstrim $mount_point' periodically\n"
                    fi
                fi
            fi
        fi
        
        # === I/O Statistics ===
        if [[ "$STORAGE_COLLECT_IO_STATS" == "true" ]]; then
            telemetry_data+="\n--- I/O Statistics ---\n"
            
            local dev_name=$(basename "$device")
            local io_stats=$(cat /proc/diskstats 2>/dev/null | grep " ${dev_name} " | head -1)
            
            if [[ -n "$io_stats" ]]; then
                local reads_completed=$(echo "$io_stats" | awk '{print $4}')
                local reads_merged=$(echo "$io_stats" | awk '{print $5}')
                local sectors_read=$(echo "$io_stats" | awk '{print $6}')
                local writes_completed=$(echo "$io_stats" | awk '{print $8}')
                local writes_merged=$(echo "$io_stats" | awk '{print $9}')
                local sectors_written=$(echo "$io_stats" | awk '{print $10}')
                local io_in_progress=$(echo "$io_stats" | awk '{print $12}')
                
                telemetry_data+="Reads Completed: $reads_completed\n"
                telemetry_data+="Writes Completed: $writes_completed\n"
                telemetry_data+="Sectors Read: $sectors_read\n"
                telemetry_data+="Sectors Written: $sectors_written\n"
                telemetry_data+="I/O in Progress: $io_in_progress\n"
                
                json_data+="\"io_stats\": {"
                json_data+="\"reads_completed\": $reads_completed,"
                json_data+="\"writes_completed\": $writes_completed,"
                json_data+="\"sectors_read\": $sectors_read,"
                json_data+="\"sectors_written\": $sectors_written,"
                json_data+="\"io_in_progress\": $io_in_progress"
                json_data+="},"
                
                # Current I/O utilization
                if command_exists iostat; then
                    local util=$(iostat -x "$device" 1 2 2>/dev/null | tail -1 | awk '{print $(NF)}')
                    if [[ -n "$util" ]]; then
                        telemetry_data+="Current Utilization: ${util}%\n"
                        json_data+="\"utilization_percent\": $util,"
                    fi
                fi
            fi
        fi
        
        # === NVMe Specific Health ===
        if [[ "$type" == "nvme" ]] && [[ "$STORAGE_COLLECT_NVME_HEALTH" == "true" ]] && command_exists nvme; then
            telemetry_data+="\n--- NVMe Health ---\n"
            
            local nvme_health=$(nvme smart-log "$device" 2>/dev/null)
            
            # Critical warnings
            local critical_warning=$(echo "$nvme_health" | grep "critical_warning" | awk '{print $3}')
            telemetry_data+="Critical Warning: $critical_warning\n"
            json_data+="\"nvme_critical_warning\": $critical_warning,"
            
            # Media errors
            local media_errors=$(echo "$nvme_health" | grep "media_errors" | awk '{print $3}')
            telemetry_data+="Media Errors: $media_errors\n"
            json_data+="\"nvme_media_errors\": $media_errors,"
            
            # Error log entries
            local error_entries=$(echo "$nvme_health" | grep "num_err_log_entries" | awk '{print $3}')
            telemetry_data+="Error Log Entries: $error_entries\n"
            json_data+="\"nvme_error_log_entries\": $error_entries,"
            
            # Warning composite temperature time
            local warning_temp_time=$(echo "$nvme_health" | grep "warning_temp_time" | awk '{print $3}')
            telemetry_data+="Warning Temp Time: $warning_temp_time\n"
            json_data+="\"nvme_warning_temp_time\": $warning_temp_time,"
        fi
        
        # === Error Counts ===
        if command_exists smartctl; then
            local error_count=$(smartctl -l error "$device" 2>/dev/null | grep -c "Error [0-9]" || echo "0")
            if [[ "$error_count" -gt 0 ]]; then
                telemetry_data+="\n--- Errors ---\n"
                telemetry_data+="SMART Error Count: $error_count\n"
                json_data+="\"error_count\": $error_count,"
            else
                json_data+="\"error_count\": 0,"
            fi
        fi
        
        # Close device JSON
        json_data="${json_data%,}}"
        ((device_count++))
        
    done <<< "$devices"
    
    # Close JSON array
    json_data+="],"
    
    # === Overall Storage Summary ===
    telemetry_data+="\n=== Storage Summary ===\n"
    telemetry_data+="Total Devices: $device_count\n"
    
    local total_space=$(df -h --total 2>/dev/null | tail -1 | awk '{print $2}' || echo "Unknown")
    local used_space=$(df -h --total 2>/dev/null | tail -1 | awk '{print $3}' || echo "Unknown")
    local available_space=$(df -h --total 2>/dev/null | tail -1 | awk '{print $4}' || echo "Unknown")
    local usage_percent=$(df -h --total 2>/dev/null | tail -1 | awk '{print $5}' || echo "Unknown")
    
    telemetry_data+="Total Filesystem Space: $total_space\n"
    telemetry_data+="Used: $used_space ($usage_percent)\n"
    telemetry_data+="Available: $available_space\n"
    
    json_data+="\"summary\": {"
    json_data+="\"total_devices\": $device_count,"
    json_data+="\"total_space\": \"$total_space\","
    json_data+="\"used_space\": \"$used_space\","
    json_data+="\"available_space\": \"$available_space\","
    json_data+="\"usage_percent\": \"$usage_percent\""
    json_data+="}"
    
    # Close JSON
    json_data+="}"
    
    # Log the telemetry
    log_telemetry "Storage" "$telemetry_data"
    
    # Add to JSON output
    json_add_module "storage" "$json_data"
    
    log_message "INFO" "Storage telemetry collection complete"
}

# Export function
export -f collect_storage_telemetry
