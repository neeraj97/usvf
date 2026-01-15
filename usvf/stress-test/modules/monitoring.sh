#!/bin/bash
# Real-time Monitoring Module

start_monitoring() {
    local DURATION=$1
    local OUTPUT=$2
    local PID_LIST=$3
    
    local LOG_FILE="$OUTPUT/logs/monitoring.log"
    local TELEMETRY_CSV="$OUTPUT/raw_data/telemetry.csv"
    local SENSORS_LOG="$OUTPUT/raw_data/sensors_timeline.log"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting real-time monitoring" | tee "$LOG_FILE"
    echo "Duration: $DURATION seconds" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # Create CSV header
    echo "Timestamp,CPU_Temp_Avg,CPU_Temp_Max,Fan_Speed_Avg,Power_Watts,EDAC_CE,EDAC_UE,CPU_Usage,Mem_Usage_Pct,Disk_IO_Read,Disk_IO_Write" > "$TELEMETRY_CSV"
    
    # Monitoring interval (seconds)
    local INTERVAL=5
    local START_TIME=$(date +%s)
    local END_TIME=$((START_TIME + DURATION))
    
    # Initialize baseline sensor readings
    if [[ "$BMC_AVAILABLE" == "yes" ]]; then
        ipmitool sdr list full > "$OUTPUT/raw_data/sensors_baseline.txt"
    fi
    
    # Thermal threshold for emergency shutdown
    local THERMAL_LIMIT=95
    
    echo "[→] Monitoring loop started. Press Ctrl+C to stop." | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # Main monitoring loop
    while [[ $(date +%s) -lt $END_TIME ]]; do
        local TS=$(date '+%Y-%m-%d %H:%M:%S')
        local TS_UNIX=$(date +%s)
        
        # --- CPU Temperature ---
        local CPU_TEMP_AVG=0
        local CPU_TEMP_MAX=0
        
        # Try sensors first (lm-sensors)
        if command -v sensors &> /dev/null; then
            # Get all core temps
            local TEMPS=$(sensors 2>/dev/null | grep -i "Core\|Package" | grep -oP '\+\K[0-9.]+' | head -20)
            if [[ -n "$TEMPS" ]]; then
                local TEMP_COUNT=0
                local TEMP_SUM=0
                while IFS= read -r temp; do
                    TEMP_SUM=$(echo "$TEMP_SUM + $temp" | bc)
                    TEMP_COUNT=$((TEMP_COUNT + 1))
                    # Track max
                    if (( $(echo "$temp > $CPU_TEMP_MAX" | bc -l) )); then
                        CPU_TEMP_MAX=$temp
                    fi
                done <<< "$TEMPS"
                
                if [[ $TEMP_COUNT -gt 0 ]]; then
                    CPU_TEMP_AVG=$(echo "scale=1; $TEMP_SUM / $TEMP_COUNT" | bc)
                fi
            fi
        fi
        
        # Fallback to IPMI if sensors didn't work
        if [[ "$CPU_TEMP_AVG" == "0" ]] && [[ "$BMC_AVAILABLE" == "yes" ]]; then
            local IPMI_TEMPS=$(ipmitool sdr list full 2>/dev/null | grep -i "temp" | grep -E "CPU|Pkg|Processor" | awk '{print $3}' | grep -oP '[0-9]+')
            if [[ -n "$IPMI_TEMPS" ]]; then
                local TEMP_COUNT=0
                local TEMP_SUM=0
                while IFS= read -r temp; do
                    [[ -z "$temp" ]] && continue
                    TEMP_SUM=$((TEMP_SUM + temp))
                    TEMP_COUNT=$((TEMP_COUNT + 1))
                    if [[ $temp -gt ${CPU_TEMP_MAX%.*} ]]; then
                        CPU_TEMP_MAX=$temp
                    fi
                done <<< "$IPMI_TEMPS"
                
                if [[ $TEMP_COUNT -gt 0 ]]; then
                    CPU_TEMP_AVG=$((TEMP_SUM / TEMP_COUNT))
                fi
            fi
        fi
        
        # --- Fan Speeds ---
        local FAN_SPEED_AVG=0
        
        # Try sensors first
        if command -v sensors &> /dev/null; then
            local FAN_SPEEDS=$(sensors 2>/dev/null | grep -i "fan" | grep -oP '\d+(?= RPM)' | grep -v "^0$")
            if [[ -n "$FAN_SPEEDS" ]]; then
                local FAN_COUNT=0
                local FAN_SUM=0
                while IFS= read -r speed; do
                    [[ -z "$speed" ]] && continue
                    FAN_SUM=$((FAN_SUM + speed))
                    FAN_COUNT=$((FAN_COUNT + 1))
                done <<< "$FAN_SPEEDS"
                
                if [[ $FAN_COUNT -gt 0 ]]; then
                    FAN_SPEED_AVG=$((FAN_SUM / FAN_COUNT))
                fi
            fi
        fi
        
        # Fallback to IPMI
        if [[ "$FAN_SPEED_AVG" == "0" ]] && [[ "$BMC_AVAILABLE" == "yes" ]]; then
            local IPMI_FANS=$(ipmitool sdr list full 2>/dev/null | grep -i "fan" | grep "RPM" | awk '{print $3}' | grep -v "^0$")
            if [[ -n "$IPMI_FANS" ]]; then
                local FAN_COUNT=0
                local FAN_SUM=0
                while IFS= read -r speed; do
                    [[ -z "$speed" ]] && continue
                    FAN_SUM=$((FAN_SUM + speed))
                    FAN_COUNT=$((FAN_COUNT + 1))
                done <<< "$IPMI_FANS"
                
                if [[ $FAN_COUNT -gt 0 ]]; then
                    FAN_SPEED_AVG=$((FAN_SUM / FAN_COUNT))
                fi
            fi
        fi
        
        # --- Power Consumption ---
        local POWER_WATTS=0
        if [[ "$BMC_AVAILABLE" == "yes" ]]; then
            POWER_WATTS=$(ipmitool dcmi power reading 2>/dev/null | grep "Instantaneous" | awk '{print $4}' || echo "0")
        fi
        
        # --- Memory Errors (EDAC) ---
        local EDAC_CE=0
        local EDAC_UE=0
        if [[ -d /sys/devices/system/edac/mc ]]; then
            EDAC_CE=$(cat /sys/devices/system/edac/mc/mc*/ce_count 2>/dev/null | awk '{s+=$1} END {print s}')
            EDAC_UE=$(cat /sys/devices/system/edac/mc/mc*/ue_count 2>/dev/null | awk '{s+=$1} END {print s}')
        fi
        
        # --- CPU Usage ---
        local CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
        
        # --- Memory Usage ---
        local MEM_USAGE_PCT=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
        
        # --- Disk I/O ---
        local DISK_READ=0
        local DISK_WRITE=0
        if command -v iostat &> /dev/null; then
            local IO_STATS=$(iostat -d -x 1 2 | tail -1)
            DISK_READ=$(echo "$IO_STATS" | awk '{print $6}' || echo "0")
            DISK_WRITE=$(echo "$IO_STATS" | awk '{print $7}' || echo "0")
        fi
        
        # --- Log to CSV ---
        echo "$TS,$CPU_TEMP_AVG,$CPU_TEMP_MAX,$FAN_SPEED_AVG,$POWER_WATTS,$EDAC_CE,$EDAC_UE,$CPU_USAGE,$MEM_USAGE_PCT,$DISK_READ,$DISK_WRITE" >> "$TELEMETRY_CSV"
        
        # --- Full sensor dump (every 30 seconds) ---
        if [[ $((TS_UNIX % 30)) -eq 0 ]]; then
            echo "=== $TS ===" >> "$SENSORS_LOG"
            if command -v sensors &> /dev/null; then
                sensors >> "$SENSORS_LOG" 2>/dev/null
            fi
            if [[ "$BMC_AVAILABLE" == "yes" ]]; then
                ipmitool sdr list full >> "$SENSORS_LOG" 2>/dev/null
            fi
            echo "" >> "$SENSORS_LOG"
        fi
        
        # --- Live Dashboard Display ---
        printf "\r[%s] Temp: %s°C (Max: %s°C) | Fan: %s RPM | Power: %sW | Mem Err: %s/%s | CPU: %s%% | Mem: %s%%    " \
            "$TS" "$CPU_TEMP_AVG" "$CPU_TEMP_MAX" "$FAN_SPEED_AVG" "$POWER_WATTS" "$EDAC_CE" "$EDAC_UE" "$CPU_USAGE" "$MEM_USAGE_PCT"
        
        # --- Thermal Safety Check ---
        if (( $(echo "$CPU_TEMP_MAX > $THERMAL_LIMIT" | bc -l) )); then
            echo "" | tee -a "$LOG_FILE"
            echo "" | tee -a "$LOG_FILE"
            echo "╔════════════════════════════════════════════╗" | tee -a "$LOG_FILE"
            echo "║   CRITICAL THERMAL EVENT DETECTED!         ║" | tee -a "$LOG_FILE"
            echo "║   CPU Temperature: ${CPU_TEMP_MAX}°C (Limit: ${THERMAL_LIMIT}°C)  ║" | tee -a "$LOG_FILE"
            echo "║   EMERGENCY SHUTDOWN INITIATED             ║" | tee -a "$LOG_FILE"
            echo "╚════════════════════════════════════════════╝" | tee -a "$LOG_FILE"
            
            # Kill all stress processes
            for pid in $PID_LIST; do
                kill -TERM $pid 2>/dev/null || true
            done
            
            pkill -f stress-ng 2>/dev/null || true
            pkill -f fio 2>/dev/null || true
            pkill -f iperf3 2>/dev/null || true
            
            break
        fi
        
        # --- Check if any memory errors occurred ---
        if [[ "${EDAC_UE:-0}" -gt 0 ]]; then
            echo "" | tee -a "$LOG_FILE"
            echo "[!!!] WARNING: Uncorrectable memory errors detected: $EDAC_UE" | tee -a "$LOG_FILE"
        fi
        
        sleep "$INTERVAL"
    done
    
    echo "" | tee -a "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Monitoring complete" | tee -a "$LOG_FILE"
    
    # Final sensor snapshot
    if [[ "$BMC_AVAILABLE" == "yes" ]]; then
        ipmitool sdr list full > "$OUTPUT/raw_data/sensors_final.txt"
    fi
    if command -v sensors &> /dev/null; then
        sensors > "$OUTPUT/raw_data/sensors_final_lm.txt" 2>/dev/null
    fi
}
