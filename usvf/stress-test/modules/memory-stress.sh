#!/bin/bash
# Memory Stress Testing Module

start_memory_stress() {
    local CORES=$1
    local DURATION=$2
    local OUTPUT=$3
    
    local LOG_FILE="$OUTPUT/logs/memory_stress.log"
    local RESULTS_FILE="$OUTPUT/raw_data/memory_results.yaml"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Memory stress test" | tee "$LOG_FILE"
    echo "Assigned Cores: $CORES" | tee -a "$LOG_FILE"
    echo "Duration: $DURATION seconds" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # Get total memory
    local TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local TOTAL_MEM_GB=$((TOTAL_MEM_KB / 1024 / 1024))
    
    # Use 85% of total memory to avoid OOM killer
    local MEM_STRESS_BYTES=$((TOTAL_MEM_KB * 85 / 100 * 1024))
    local MEM_STRESS_GB=$((MEM_STRESS_BYTES / 1024 / 1024 / 1024))
    
    echo "Total Memory: ${TOTAL_MEM_GB} GB" | tee -a "$LOG_FILE"
    echo "Stress Target: ${MEM_STRESS_GB} GB (85%)" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # Run memory stress with verification
    echo "[→] Running memory stress with data integrity verification..." | tee -a "$LOG_FILE"
    stress-ng \
        --vm "$CORES" \
        --vm-bytes "${MEM_STRESS_GB}G" \
        --vm-method all \
        --verify \
        --timeout "$DURATION" \
        --metrics-brief \
        --yaml "$RESULTS_FILE" \
        --log-file "$LOG_FILE" &
    
    local PID_VM=$!
    echo "Memory stress PID: $PID_VM" | tee -a "$LOG_FILE"
    wait $PID_VM
    
    # Additional memory bandwidth test
    echo "" | tee -a "$LOG_FILE"
    echo "[→] Running memory bandwidth test..." | tee -a "$LOG_FILE"
    
    # Run sysbench memory test if available
    if command -v sysbench &> /dev/null; then
        sysbench memory \
            --memory-block-size=1M \
            --memory-total-size=100G \
            --threads="$CORES" \
            run | tee -a "$LOG_FILE" > "$OUTPUT/raw_data/sysbench_memory.txt"
    else
        echo "[!] sysbench not available, skipping bandwidth test" | tee -a "$LOG_FILE"
    fi
    
    # Memory latency test
    echo "" | tee -a "$LOG_FILE"
    echo "[→] Running memory latency test..." | tee -a "$LOG_FILE"
    stress-ng \
        --cache "$CORES" \
        --cache-size 16M \
        --timeout $((DURATION / 3)) \
        --metrics-brief \
        --yaml "${RESULTS_FILE}.cache" \
        --log-file "$LOG_FILE" &
    
    local PID_CACHE=$!
    wait $PID_CACHE
    
    # Check for memory errors
    echo "" | tee -a "$LOG_FILE"
    echo "[→] Checking for memory errors..." | tee -a "$LOG_FILE"
    
    # EDAC error counters
    if [[ -d /sys/devices/system/edac/mc ]]; then
        EDAC_CE=$(cat /sys/devices/system/edac/mc/mc*/ce_count 2>/dev/null | awk '{s+=$1} END {print s}')
        EDAC_UE=$(cat /sys/devices/system/edac/mc/mc*/ue_count 2>/dev/null | awk '{s+=$1} END {print s}')
        
        echo "EDAC Correctable Errors: ${EDAC_CE:-0}" | tee -a "$LOG_FILE"
        echo "EDAC Uncorrectable Errors: ${EDAC_UE:-0}" | tee -a "$LOG_FILE"
        
        if [[ "${EDAC_UE:-0}" -gt 0 ]]; then
            echo "[!] WARNING: Uncorrectable memory errors detected!" | tee -a "$LOG_FILE"
        fi
    else
        echo "[i] EDAC not available on this system" | tee -a "$LOG_FILE"
    fi
    
    echo "" | tee -a "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Memory stress test complete" | tee -a "$LOG_FILE"
}
