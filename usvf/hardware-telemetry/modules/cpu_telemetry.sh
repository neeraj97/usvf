#!/bin/bash
# CPU Telemetry Module
# Collects comprehensive CPU metrics including frequency, temperature, throttling, cache, and power

collect_cpu_telemetry() {
    if [[ "$ENABLE_CPU_TELEMETRY" != "true" ]]; then
        return
    fi
    
    local telemetry_data=""
    local json_data="{"
    
    log_message "INFO" "Collecting CPU telemetry..."
    
    # === CPU Basic Information ===
    local cpu_model=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    local cpu_cores=$(nproc)
    local cpu_threads=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
    local cpu_sockets=$(lscpu | grep "Socket(s):" | awk '{print $2}')
    local cpu_architecture=$(uname -m)
    
    telemetry_data+="CPU Model: $cpu_model\n"
    telemetry_data+="Architecture: $cpu_architecture\n"
    telemetry_data+="Sockets: $cpu_sockets\n"
    telemetry_data+="Cores: $cpu_cores\n"
    telemetry_data+="Threads: $cpu_threads\n"
    
    json_data+="\"model\": \"$cpu_model\","
    json_data+="\"architecture\": \"$cpu_architecture\","
    json_data+="\"sockets\": $cpu_sockets,"
    json_data+="\"cores\": $cpu_cores,"
    json_data+="\"threads\": $cpu_threads,"
    
    # === CPU Frequency ===
    if [[ "$CPU_COLLECT_FREQUENCY" == "true" ]]; then
        telemetry_data+="\n--- CPU Frequency ---\n"
        json_data+="\"frequency\": {"
        
        # Current frequency for each CPU
        local freq_data="["
        local cpu_num=0
        while [[ $cpu_num -lt $cpu_threads ]]; do
            local current_freq=$(cat /sys/devices/system/cpu/cpu${cpu_num}/cpufreq/scaling_cur_freq 2>/dev/null || echo "0")
            local min_freq=$(cat /sys/devices/system/cpu/cpu${cpu_num}/cpufreq/scaling_min_freq 2>/dev/null || echo "0")
            local max_freq=$(cat /sys/devices/system/cpu/cpu${cpu_num}/cpufreq/scaling_max_freq 2>/dev/null || echo "0")
            local governor=$(cat /sys/devices/system/cpu/cpu${cpu_num}/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
            
            # Convert kHz to MHz
            current_freq=$(echo "scale=2; $current_freq / 1000" | bc)
            min_freq=$(echo "scale=2; $min_freq / 1000" | bc)
            max_freq=$(echo "scale=2; $max_freq / 1000" | bc)
            
            telemetry_data+="CPU $cpu_num: Current=${current_freq}MHz, Min=${min_freq}MHz, Max=${max_freq}MHz, Governor=${governor}\n"
            
            [[ $cpu_num -gt 0 ]] && freq_data+=","
            freq_data+="{\"cpu\": $cpu_num, \"current_mhz\": $current_freq, \"min_mhz\": $min_freq, \"max_mhz\": $max_freq, \"governor\": \"$governor\"}"
            
            ((cpu_num++))
        done
        freq_data+="]"
        json_data+="\"per_cpu\": $freq_data,"
        
        # Average frequency
        local avg_freq=$(cat /proc/cpuinfo | grep "^cpu MHz" | awk '{sum+=$4; count++} END {if(count>0) print sum/count; else print 0}')
        telemetry_data+="Average Frequency: ${avg_freq}MHz\n"
        json_data+="\"average_mhz\": $avg_freq"
        json_data+="},"
    fi
    
    # === CPU Utilization ===
    telemetry_data+="\n--- CPU Utilization ---\n"
    
    # Overall CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    telemetry_data+="Overall CPU Usage: ${cpu_usage}%\n"
    
    # Per-core usage using mpstat if available
    if command_exists mpstat; then
        local per_core_usage=$(mpstat -P ALL 1 1 2>/dev/null | grep -v "Average" | grep -v "Linux" | tail -n +4)
        telemetry_data+="Per-Core Usage:\n$per_core_usage\n"
    fi
    
    # Load averages
    local load_avg=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
    telemetry_data+="Load Average (1/5/15 min): $load_avg\n"
    
    json_data+="\"utilization\": {"
    json_data+="\"overall_percent\": $cpu_usage,"
    json_data+="\"load_average\": \"$load_avg\""
    json_data+="},"
    
    # === CPU Temperature ===
    if [[ "$CPU_COLLECT_TEMPERATURE" == "true" ]]; then
        telemetry_data+="\n--- CPU Temperature ---\n"
        json_data+="\"temperature\": {"
        
        local temp_data="["
        local temp_found=false
        
        # Try sensors command first
        if command_exists sensors; then
            local sensor_output=$(sensors 2>/dev/null)
            
            # Core temperatures
            local core_temps=$(echo "$sensor_output" | grep -E "Core [0-9]+:" | awk '{print $3}' | tr -d '+°C')
            if [[ -n "$core_temps" ]]; then
                temp_found=true
                local core_num=0
                while IFS= read -r temp; do
                    telemetry_data+="Core $core_num: ${temp}°C\n"
                    [[ $core_num -gt 0 ]] && temp_data+=","
                    temp_data+="{\"core\": $core_num, \"celsius\": $temp}"
                    ((core_num++))
                done <<< "$core_temps"
            fi
            
            # Package temperature
            local pkg_temp=$(echo "$sensor_output" | grep "Package id 0:" | awk '{print $4}' | tr -d '+°C')
            if [[ -n "$pkg_temp" ]]; then
                telemetry_data+="Package Temperature: ${pkg_temp}°C\n"
                json_data+="\"package_celsius\": $pkg_temp,"
            fi
        fi
        
        # Fallback to thermal zones
        if [[ "$temp_found" == "false" ]] && [[ -d /sys/class/thermal ]]; then
            local zone_num=0
            for zone in /sys/class/thermal/thermal_zone*/temp; do
                if [[ -f "$zone" ]]; then
                    local temp=$(cat "$zone")
                    temp=$(millidegree_to_celsius "$temp")
                    local zone_type=$(cat "$(dirname "$zone")/type" 2>/dev/null || echo "unknown")
                    
                    telemetry_data+="Thermal Zone $zone_num ($zone_type): ${temp}°C\n"
                    [[ $zone_num -gt 0 ]] && temp_data+=","
                    temp_data+="{\"zone\": $zone_num, \"type\": \"$zone_type\", \"celsius\": $temp}"
                    ((zone_num++))
                fi
            done
        fi
        
        temp_data+="]"
        json_data+="\"sensors\": $temp_data"
        json_data+="},"
    fi
    
    # === CPU Cache Statistics ===
    if [[ "$CPU_COLLECT_CACHE_STATS" == "true" ]]; then
        telemetry_data+="\n--- CPU Cache ---\n"
        
        local l1d_cache=$(lscpu | grep "L1d cache:" | awk '{print $3}')
        local l1i_cache=$(lscpu | grep "L1i cache:" | awk '{print $3}')
        local l2_cache=$(lscpu | grep "L2 cache:" | awk '{print $3}')
        local l3_cache=$(lscpu | grep "L3 cache:" | awk '{print $3}')
        
        telemetry_data+="L1d Cache: $l1d_cache\n"
        telemetry_data+="L1i Cache: $l1i_cache\n"
        telemetry_data+="L2 Cache: $l2_cache\n"
        telemetry_data+="L3 Cache: $l3_cache\n"
        
        json_data+="\"cache\": {"
        json_data+="\"l1d\": \"$l1d_cache\","
        json_data+="\"l1i\": \"$l1i_cache\","
        json_data+="\"l2\": \"$l2_cache\","
        json_data+="\"l3\": \"$l3_cache\""
        json_data+="},"
        
        # Cache statistics from perf if available
        if command_exists perf; then
            local cache_stats=$(perf stat -e cache-references,cache-misses -a sleep 1 2>&1 | grep -E "cache-references|cache-misses" || echo "")
            if [[ -n "$cache_stats" ]]; then
                telemetry_data+="Cache Statistics:\n$cache_stats\n"
            fi
        fi
    fi
    
    # === CPU Throttling ===
    if [[ "$CPU_COLLECT_THROTTLING" == "true" ]]; then
        telemetry_data+="\n--- CPU Throttling ---\n"
        json_data+="\"throttling\": {"
        
        # Check for thermal throttling
        if [[ -f /sys/devices/system/cpu/cpu0/thermal_throttle/core_throttle_count ]]; then
            local throttle_data="["
            local cpu_num=0
            while [[ $cpu_num -lt $cpu_threads ]]; do
                local core_throttle=$(cat /sys/devices/system/cpu/cpu${cpu_num}/thermal_throttle/core_throttle_count 2>/dev/null || echo "0")
                local pkg_throttle=$(cat /sys/devices/system/cpu/cpu${cpu_num}/thermal_throttle/package_throttle_count 2>/dev/null || echo "0")
                
                telemetry_data+="CPU $cpu_num: Core Throttle Count=$core_throttle, Package Throttle Count=$pkg_throttle\n"
                
                [[ $cpu_num -gt 0 ]] && throttle_data+=","
                throttle_data+="{\"cpu\": $cpu_num, \"core_count\": $core_throttle, \"package_count\": $pkg_throttle}"
                
                ((cpu_num++))
            done
            throttle_data+="]"
            json_data+="\"events\": $throttle_data"
        else
            telemetry_data+="Throttling information not available\n"
            json_data+="\"events\": []"
        fi
        json_data+="},"
    fi
    
    # === CPU Power Consumption ===
    if [[ "$CPU_COLLECT_POWER" == "true" ]]; then
        telemetry_data+="\n--- CPU Power ---\n"
        json_data+="\"power\": {"
        
        local power_data_found=false
        
        # Try RAPL (Running Average Power Limit) interface
        if [[ -d /sys/class/powercap/intel-rapl ]]; then
            for rapl in /sys/class/powercap/intel-rapl/intel-rapl:*/; do
                if [[ -f "${rapl}name" ]]; then
                    local domain=$(cat "${rapl}name")
                    local energy=$(cat "${rapl}energy_uj" 2>/dev/null || echo "0")
                    local max_energy=$(cat "${rapl}max_energy_range_uj" 2>/dev/null || echo "0")
                    
                    # Convert microjoules to joules
                    energy=$(echo "scale=3; $energy / 1000000" | bc)
                    max_energy=$(echo "scale=3; $max_energy / 1000000" | bc)
                    
                    telemetry_data+="Domain: $domain, Energy: ${energy}J, Max: ${max_energy}J\n"
                    power_data_found=true
                fi
            done
        fi
        
        # Try turbostat if available
        if command_exists turbostat && [[ "$power_data_found" == "false" ]]; then
            local turbo_output=$(timeout 2 turbostat --quiet --show PkgWatt,CorWatt --interval 1 2>/dev/null | tail -1)
            if [[ -n "$turbo_output" ]]; then
                telemetry_data+="Power (turbostat): $turbo_output\n"
                power_data_found=true
            fi
        fi
        
        if [[ "$power_data_found" == "false" ]]; then
            telemetry_data+="Power information not available\n"
            json_data+="\"available\": false"
        else
            json_data+="\"available\": true"
        fi
        json_data+="},"
    fi
    
    # === CPU Context Switches and Interrupts ===
    telemetry_data+="\n--- CPU Activity ---\n"
    local context_switches=$(cat /proc/stat | grep "^ctxt" | awk '{print $2}')
    local interrupts=$(cat /proc/stat | grep "^intr" | awk '{print $2}')
    local processes=$(cat /proc/stat | grep "^processes" | awk '{print $2}')
    
    telemetry_data+="Context Switches: $context_switches\n"
    telemetry_data+="Interrupts: $interrupts\n"
    telemetry_data+="Processes Created: $processes\n"
    
    json_data+="\"activity\": {"
    json_data+="\"context_switches\": $context_switches,"
    json_data+="\"interrupts\": $interrupts,"
    json_data+="\"processes_created\": $processes"
    json_data+="}"
    
    # Close JSON
    json_data+="}"
    
    # Log the telemetry
    log_telemetry "CPU" "$telemetry_data"
    
    # Add to JSON output
    json_add_module "cpu" "$json_data"
    
    log_message "INFO" "CPU telemetry collection complete"
}

# Export function
export -f collect_cpu_telemetry
