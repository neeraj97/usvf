#!/bin/bash
# Memory Telemetry Module
# Collects comprehensive memory metrics including usage, bandwidth, errors, temperature, and per-DIMM statistics

collect_memory_telemetry() {
    if [[ "$ENABLE_MEMORY_TELEMETRY" != "true" ]]; then
        return
    fi
    
    local telemetry_data=""
    local json_data="{"
    
    log_message "INFO" "Collecting Memory telemetry..."
    
    # === Memory Basic Information ===
    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_gb=$(echo "scale=2; $total_mem_kb / 1024 / 1024" | bc)
    local available_mem_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    local available_mem_gb=$(echo "scale=2; $available_mem_kb / 1024 / 1024" | bc)
    local free_mem_kb=$(grep MemFree /proc/meminfo | awk '{print $2}')
    local free_mem_gb=$(echo "scale=2; $free_mem_kb / 1024 / 1024" | bc)
    local used_mem_kb=$((total_mem_kb - available_mem_kb))
    local used_mem_gb=$(echo "scale=2; $used_mem_kb / 1024 / 1024" | bc)
    local used_percent=$(format_percentage $used_mem_kb $total_mem_kb)
    
    telemetry_data+="Total Memory: ${total_mem_gb}GB\n"
    telemetry_data+="Used Memory: ${used_mem_gb}GB (${used_percent})\n"
    telemetry_data+="Available Memory: ${available_mem_gb}GB\n"
    telemetry_data+="Free Memory: ${free_mem_gb}GB\n"
    
    json_data+="\"total_gb\": $total_mem_gb,"
    json_data+="\"used_gb\": $used_mem_gb,"
    json_data+="\"available_gb\": $available_mem_gb,"
    json_data+="\"free_gb\": $free_mem_gb,"
    json_data+="\"used_percent\": ${used_percent//\%/},"
    
    # === Buffer and Cache ===
    local buffers_kb=$(grep Buffers /proc/meminfo | awk '{print $2}')
    local cached_kb=$(grep "^Cached:" /proc/meminfo | awk '{print $2}')
    local buffers_gb=$(echo "scale=2; $buffers_kb / 1024 / 1024" | bc)
    local cached_gb=$(echo "scale=2; $cached_kb / 1024 / 1024" | bc)
    
    telemetry_data+="Buffers: ${buffers_gb}GB\n"
    telemetry_data+="Cached: ${cached_gb}GB\n"
    
    json_data+="\"buffers_gb\": $buffers_gb,"
    json_data+="\"cached_gb\": $cached_gb,"
    
    # === Swap Information ===
    local swap_total_kb=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
    local swap_free_kb=$(grep SwapFree /proc/meminfo | awk '{print $2}')
    local swap_used_kb=$((swap_total_kb - swap_free_kb))
    local swap_total_gb=$(echo "scale=2; $swap_total_kb / 1024 / 1024" | bc)
    local swap_used_gb=$(echo "scale=2; $swap_used_kb / 1024 / 1024" | bc)
    
    telemetry_data+="\n--- Swap ---\n"
    telemetry_data+="Total Swap: ${swap_total_gb}GB\n"
    telemetry_data+="Used Swap: ${swap_used_gb}GB\n"
    
    if [[ $swap_total_kb -gt 0 ]]; then
        local swap_percent=$(format_percentage $swap_used_kb $swap_total_kb)
        telemetry_data+="Swap Usage: ${swap_percent}\n"
        json_data+="\"swap\": {\"total_gb\": $swap_total_gb, \"used_gb\": $swap_used_gb, \"used_percent\": ${swap_percent//\%/}},"
    else
        json_data+="\"swap\": {\"total_gb\": 0, \"used_gb\": 0, \"used_percent\": 0},"
    fi
    
    # === Huge Pages ===
    if grep -q "HugePages_Total" /proc/meminfo; then
        local hugepages_total=$(grep HugePages_Total /proc/meminfo | awk '{print $2}')
        local hugepages_free=$(grep HugePages_Free /proc/meminfo | awk '{print $2}')
        local hugepages_size_kb=$(grep Hugepagesize /proc/meminfo | awk '{print $2}')
        local hugepages_used=$((hugepages_total - hugepages_free))
        
        telemetry_data+="\n--- Huge Pages ---\n"
        telemetry_data+="Total Huge Pages: $hugepages_total\n"
        telemetry_data+="Used Huge Pages: $hugepages_used\n"
        telemetry_data+="Huge Page Size: ${hugepages_size_kb}KB\n"
        
        json_data+="\"hugepages\": {\"total\": $hugepages_total, \"used\": $hugepages_used, \"size_kb\": $hugepages_size_kb},"
    fi
    
    # === Per-DIMM Information ===
    if [[ "$MEMORY_COLLECT_PER_DIMM" == "true" ]] && command_exists dmidecode; then
        telemetry_data+="\n--- DIMM Information ---\n"
        json_data+="\"dimms\": ["
        
        local dimm_count=0
        local in_memory_device=false
        local dimm_size=""
        local dimm_type=""
        local dimm_speed=""
        local dimm_manufacturer=""
        local dimm_serial=""
        local dimm_locator=""
        
        while IFS= read -r line; do
            if [[ "$line" =~ ^"Memory Device" ]]; then
                # Save previous DIMM if it exists
                if [[ -n "$dimm_size" ]] && [[ "$dimm_size" != "No Module Installed" ]]; then
                    [[ $dimm_count -gt 0 ]] && json_data+=","
                    
                    telemetry_data+="DIMM $dimm_locator:\n"
                    telemetry_data+="  Size: $dimm_size\n"
                    telemetry_data+="  Type: $dimm_type\n"
                    telemetry_data+="  Speed: $dimm_speed\n"
                    telemetry_data+="  Manufacturer: $dimm_manufacturer\n"
                    telemetry_data+="  Serial: $dimm_serial\n"
                    
                    json_data+="{\"locator\": \"$dimm_locator\", \"size\": \"$dimm_size\", \"type\": \"$dimm_type\", \"speed\": \"$dimm_speed\", \"manufacturer\": \"$dimm_manufacturer\", \"serial\": \"$dimm_serial\"}"
                    ((dimm_count++))
                fi
                
                # Reset for new DIMM
                in_memory_device=true
                dimm_size=""
                dimm_type=""
                dimm_speed=""
                dimm_manufacturer=""
                dimm_serial=""
                dimm_locator=""
            elif [[ "$in_memory_device" == "true" ]]; then
                if [[ "$line" =~ Size:\ (.+) ]]; then
                    dimm_size="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ Type:\ (.+) ]]; then
                    dimm_type="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ Speed:\ (.+) ]]; then
                    dimm_speed="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ Manufacturer:\ (.+) ]]; then
                    dimm_manufacturer="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ Serial\ Number:\ (.+) ]]; then
                    dimm_serial="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ Locator:\ (.+) ]]; then
                    dimm_locator="${BASH_REMATCH[1]}"
                fi
            fi
        done < <(dmidecode -t memory 2>/dev/null)
        
        # Don't forget the last DIMM
        if [[ -n "$dimm_size" ]] && [[ "$dimm_size" != "No Module Installed" ]]; then
            [[ $dimm_count -gt 0 ]] && json_data+=","
            
            telemetry_data+="DIMM $dimm_locator:\n"
            telemetry_data+="  Size: $dimm_size\n"
            telemetry_data+="  Type: $dimm_type\n"
            telemetry_data+="  Speed: $dimm_speed\n"
            telemetry_data+="  Manufacturer: $dimm_manufacturer\n"
            telemetry_data+="  Serial: $dimm_serial\n"
            
            json_data+="{\"locator\": \"$dimm_locator\", \"size\": \"$dimm_size\", \"type\": \"$dimm_type\", \"speed\": \"$dimm_speed\", \"manufacturer\": \"$dimm_manufacturer\", \"serial\": \"$dimm_serial\"}"
        fi
        
        json_data+="],"
        telemetry_data+="Total DIMMs Installed: $dimm_count\n"
    fi
    
    # === Memory Errors ===
    if [[ "$MEMORY_COLLECT_ERRORS" == "true" ]]; then
        telemetry_data+="\n--- Memory Errors ---\n"
        json_data+="\"errors\": {"
        
        # Check EDAC (Error Detection and Correction)
        if [[ -d /sys/devices/system/edac/mc ]]; then
            local total_ce=0
            local total_ue=0
            
            for mc in /sys/devices/system/edac/mc/mc*/; do
                if [[ -f "${mc}ce_count" ]]; then
                    local ce=$(cat "${mc}ce_count" 2>/dev/null || echo "0")
                    local ue=$(cat "${mc}ue_count" 2>/dev/null || echo "0")
                    total_ce=$((total_ce + ce))
                    total_ue=$((total_ue + ue))
                fi
            done
            
            telemetry_data+="Correctable Errors: $total_ce\n"
            telemetry_data+="Uncorrectable Errors: $total_ue\n"
            
            json_data+="\"correctable\": $total_ce,"
            json_data+="\"uncorrectable\": $total_ue,"
            json_data+="\"source\": \"edac\""
        else
            telemetry_data+="EDAC not available\n"
            json_data+="\"correctable\": 0,"
            json_data+="\"uncorrectable\": 0,"
            json_data+="\"source\": \"none\""
        fi
        
        json_data+="},"
    fi
    
    # === Memory Bandwidth ===
    if [[ "$MEMORY_COLLECT_BANDWIDTH" == "true" ]]; then
        telemetry_data+="\n--- Memory Bandwidth ---\n"
        json_data+="\"bandwidth\": {"
        
        # Try to use pcm-memory if available (Intel Performance Counter Monitor)
        if command_exists pcm-memory; then
            local bandwidth_output=$(timeout 5 pcm-memory 1 2>/dev/null | grep -E "Memory|READ|WRITE" | head -10)
            if [[ -n "$bandwidth_output" ]]; then
                telemetry_data+="$bandwidth_output\n"
                json_data+="\"available\": true"
            else
                telemetry_data+="Bandwidth monitoring not available\n"
                json_data+="\"available\": false"
            fi
        # Try with perf if available
        elif command_exists perf; then
            local mem_load=$(perf stat -e mem_load_retired.l1_miss,mem_load_retired.l2_miss,mem_load_retired.l3_miss -a sleep 1 2>&1 | grep "mem_load" || echo "")
            if [[ -n "$mem_load" ]]; then
                telemetry_data+="Memory Load Events:\n$mem_load\n"
                json_data+="\"available\": true"
            else
                telemetry_data+="Bandwidth monitoring not available\n"
                json_data+="\"available\": false"
            fi
        else
            telemetry_data+="Bandwidth monitoring tools not available\n"
            json_data+="\"available\": false"
        fi
        
        json_data+="},"
    fi
    
    # === Memory Temperature ===
    if [[ "$MEMORY_COLLECT_TEMPERATURE" == "true" ]]; then
        telemetry_data+="\n--- Memory Temperature ---\n"
        json_data+="\"temperature\": {"
        
        local temp_found=false
        local temp_data="["
        
        # Try to find memory temperature sensors
        if command_exists sensors; then
            local mem_temps=$(sensors 2>/dev/null | grep -i "dimm\|mem" | grep "°C")
            if [[ -n "$mem_temps" ]]; then
                telemetry_data+="$mem_temps\n"
                temp_found=true
                
                local temp_count=0
                while IFS= read -r temp_line; do
                    local temp_value=$(echo "$temp_line" | grep -oP '\+\K[0-9.]+' | head -1)
                    if [[ -n "$temp_value" ]]; then
                        [[ $temp_count -gt 0 ]] && temp_data+=","
                        temp_data+="{\"sensor\": \"$(echo "$temp_line" | cut -d: -f1 | xargs)\", \"celsius\": $temp_value}"
                        ((temp_count++))
                    fi
                done <<< "$mem_temps"
            fi
        fi
        
        # Check IPMI for memory temperature
        if [[ "$temp_found" == "false" ]] && check_bmc_available; then
            local ipmi_mem_temps=$(ipmitool sdr type "Memory" 2>/dev/null | grep -i "temp")
            if [[ -n "$ipmi_mem_temps" ]]; then
                telemetry_data+="$ipmi_mem_temps\n"
                temp_found=true
            fi
        fi
        
        if [[ "$temp_found" == "false" ]]; then
            telemetry_data+="Memory temperature sensors not available\n"
            json_data+="\"available\": false"
        else
            temp_data+="]"
            json_data+="\"sensors\": $temp_data,"
            json_data+="\"available\": true"
        fi
        
        json_data+="},"
    fi
    
    # === NUMA Information ===
    if [[ -d /sys/devices/system/node ]]; then
        telemetry_data+="\n--- NUMA Information ---\n"
        json_data+="\"numa\": {"
        
        local numa_nodes=$(ls /sys/devices/system/node/ | grep "node[0-9]" | wc -l)
        telemetry_data+="NUMA Nodes: $numa_nodes\n"
        json_data+="\"nodes\": $numa_nodes,"
        
        if command_exists numactl; then
            local numa_stats=$(numactl --hardware 2>/dev/null)
            telemetry_data+="$numa_stats\n"
        fi
        
        json_data+="\"enabled\": true"
        json_data+="},"
    fi
    
    # === Memory Statistics ===
    telemetry_data+="\n--- Memory Statistics ---\n"
    local page_faults=$(cat /proc/vmstat | grep "pgfault " | awk '{print $2}')
    local major_faults=$(cat /proc/vmstat | grep "pgmajfault " | awk '{print $2}')
    local page_in=$(cat /proc/vmstat | grep "pgpgin " | awk '{print $2}')
    local page_out=$(cat /proc/vmstat | grep "pgpgout " | awk '{print $2}')
    
    telemetry_data+="Page Faults: $page_faults\n"
    telemetry_data+="Major Faults: $major_faults\n"
    telemetry_data+="Pages In: $page_in\n"
    telemetry_data+="Pages Out: $page_out\n"
    
    json_data+="\"statistics\": {"
    json_data+="\"page_faults\": $page_faults,"
    json_data+="\"major_faults\": $major_faults,"
    json_data+="\"pages_in\": $page_in,"
    json_data+="\"pages_out\": $page_out"
    json_data+="}"
    
    # Close JSON
    json_data+="}"
    
    # Log the telemetry
    log_telemetry "Memory" "$telemetry_data"
    
    # Add to JSON output
    json_add_module "memory" "$json_data"
    
    log_message "INFO" "Memory telemetry collection complete"
}

# Export function
export -f collect_memory_telemetry
