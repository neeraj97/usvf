#!/bin/bash
# GPU Telemetry Module
# Collects GPU metrics including temperature, usage, memory, power, fan speed, clock speed

collect_gpu_telemetry() {
    if [[ "$ENABLE_GPU_TELEMETRY" != "true" ]]; then
        return
    fi
    
    local telemetry_data=""
    local json_data="{"
    
    log_message "INFO" "Collecting GPU telemetry..."
    
    # Detect GPUs
    local gpus=$(detect_gpus)
    
    if [[ -z "$gpus" ]]; then
        telemetry_data+="No GPUs detected\n"
        json_data+="\"gpus\": []}"
        log_telemetry "GPU" "$telemetry_data"
        json_add_module "gpu" "$json_data"
        return
    fi
    
    json_data+="\"gpus\": ["
    local gpu_count=0
    
    while IFS='|' read -r vendor gpu_id; do
        [[ -z "$gpu_id" ]] && continue
        
        [[ $gpu_count -gt 0 ]] && json_data+=","
        
        telemetry_data+="\n=== GPU: $gpu_id ($vendor) ===\n"
        json_data+="{\"vendor\": \"$vendor\", \"id\": \"$gpu_id\","
        
        case "$vendor" in
            nvidia)
                if command_exists nvidia-smi; then
                    # GPU Name
                    local gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader -i "$gpu_id" 2>/dev/null || echo "Unknown")
                    telemetry_data+="Name: $gpu_name\n"
                    json_data+="\"name\": \"$gpu_name\","
                    
                    # Temperature
                    if [[ "$GPU_COLLECT_TEMPERATURE" == "true" ]]; then
                        local temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader -i "$gpu_id" 2>/dev/null || echo "0")
                        telemetry_data+="Temperature: ${temp}°C\n"
                        json_data+="\"temperature_celsius\": $temp,"
                    fi
                    
                    # GPU Usage
                    if [[ "$GPU_COLLECT_USAGE" == "true" ]]; then
                        local usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader -i "$gpu_id" 2>/dev/null | tr -d ' %' || echo "0")
                        telemetry_data+="GPU Usage: ${usage}%\n"
                        json_data+="\"usage_percent\": $usage,"
                    fi
                    
                    # Memory
                    if [[ "$GPU_COLLECT_MEMORY" == "true" ]]; then
                        local mem_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader -i "$gpu_id" 2>/dev/null | awk '{print $1}' || echo "0")
                        local mem_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader -i "$gpu_id" 2>/dev/null | awk '{print $1}' || echo "0")
                        telemetry_data+="Memory Used: ${mem_used}MB / ${mem_total}MB\n"
                        json_data+="\"memory_used_mb\": $mem_used,"
                        json_data+="\"memory_total_mb\": $mem_total,"
                    fi
                    
                    # Power
                    if [[ "$GPU_COLLECT_POWER" == "true" ]]; then
                        local power=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader -i "$gpu_id" 2>/dev/null | awk '{print $1}' || echo "0")
                        local power_limit=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader -i "$gpu_id" 2>/dev/null | awk '{print $1}' || echo "0")
                        telemetry_data+="Power Draw: ${power}W / ${power_limit}W\n"
                        json_data+="\"power_draw_watts\": $power,"
                        json_data+="\"power_limit_watts\": $power_limit,"
                    fi
                    
                    # Fan Speed
                    if [[ "$GPU_COLLECT_FAN_SPEED" == "true" ]]; then
                        local fan_speed=$(nvidia-smi --query-gpu=fan.speed --format=csv,noheader -i "$gpu_id" 2>/dev/null | tr -d ' %' || echo "0")
                        telemetry_data+="Fan Speed: ${fan_speed}%\n"
                        json_data+="\"fan_speed_percent\": $fan_speed,"
                    fi
                    
                    # Clock Speed
                    if [[ "$GPU_COLLECT_CLOCK_SPEED" == "true" ]]; then
                        local gpu_clock=$(nvidia-smi --query-gpu=clocks.gr --format=csv,noheader -i "$gpu_id" 2>/dev/null | awk '{print $1}' || echo "0")
                        local mem_clock=$(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader -i "$gpu_id" 2>/dev/null | awk '{print $1}' || echo "0")
                        telemetry_data+="GPU Clock: ${gpu_clock}MHz\n"
                        telemetry_data+="Memory Clock: ${mem_clock}MHz\n"
                        json_data+="\"gpu_clock_mhz\": $gpu_clock,"
                        json_data+="\"mem_clock_mhz\": $mem_clock,"
                    fi
                fi
                ;;
            amd)
                if command_exists rocm-smi; then
                    telemetry_data+="AMD GPU telemetry (basic)\n"
                    local temp=$(rocm-smi --showtemp 2>/dev/null | grep "Temperature" | awk '{print $3}' || echo "0")
                    local usage=$(rocm-smi --showuse 2>/dev/null | grep "GPU use" | awk '{print $4}' | tr -d '%' || echo "0")
                    
                    if [[ -n "$temp" ]]; then
                        telemetry_data+="Temperature: ${temp}°C\n"
                        json_data+="\"temperature_celsius\": $temp,"
                    fi
                    
                    if [[ -n "$usage" ]]; then
                        telemetry_data+="GPU Usage: ${usage}%\n"
                        json_data+="\"usage_percent\": $usage,"
                    fi
                fi
                ;;
            intel)
                telemetry_data+="Intel GPU detected (limited telemetry)\n"
                json_data+="\"telemetry\": \"limited\","
                ;;
        esac
        
        json_data="${json_data%,}}"
        ((gpu_count++))
        
    done <<< "$gpus"
    
    json_data+="]}"
    
    telemetry_data+="\nTotal GPUs: $gpu_count\n"
    
    log_telemetry "GPU" "$telemetry_data"
    json_add_module "gpu" "$json_data"
    
    log_message "INFO" "GPU telemetry collection complete"
}

export -f collect_gpu_telemetry
