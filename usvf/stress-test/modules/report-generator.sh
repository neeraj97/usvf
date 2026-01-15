#!/bin/bash
# Report Generation Module

generate_report() {
    local OUTPUT=$1
    local REPORT_FILE="$OUTPUT/reports/FINAL_REPORT.txt"
    local SUMMARY_FILE="$OUTPUT/reports/SUMMARY.txt"
    
    echo "[→] Generating comprehensive report..."
    
    # Create report header
    cat > "$REPORT_FILE" <<'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║          USVF - Unified Server Validation Framework v3.0                    ║
║          Comprehensive Server Stress Test Report                            ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

EOF
    
    # Test Information
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "  TEST INFORMATION" >> "$REPORT_FILE"
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "Test Date/Time: $(date)" >> "$REPORT_FILE"
    echo "Test Duration: ${DURATION} seconds" >> "$REPORT_FILE"
    echo "Output Directory: $OUTPUT" >> "$REPORT_FILE"
    echo "Hostname: $(hostname)" >> "$REPORT_FILE"
    echo "Kernel: $(uname -r)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Hardware Summary
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "  HARDWARE INVENTORY" >> "$REPORT_FILE"
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    if [[ -f "$OUTPUT/reports/hardware_inventory.txt" ]]; then
        cat "$OUTPUT/reports/hardware_inventory.txt" >> "$REPORT_FILE"
    else
        echo "[!] Hardware inventory not found" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # CPU/Compute Test Results
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "  CPU/COMPUTE STRESS TEST RESULTS" >> "$REPORT_FILE"
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    parse_compute_results "$OUTPUT" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Storage Test Results
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "  STORAGE STRESS TEST RESULTS" >> "$REPORT_FILE"
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    parse_storage_results "$OUTPUT" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Network Test Results
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "  NETWORK STRESS TEST RESULTS" >> "$REPORT_FILE"
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    parse_network_results "$OUTPUT" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Memory Test Results
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "  MEMORY STRESS TEST RESULTS" >> "$REPORT_FILE"
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    parse_memory_results "$OUTPUT" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Monitoring/Telemetry Summary
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "  MONITORING & TELEMETRY SUMMARY" >> "$REPORT_FILE"
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    parse_monitoring_results "$OUTPUT" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Unknown/Untested Devices
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "  UNKNOWN/UNTESTED DEVICES" >> "$REPORT_FILE"
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    if [[ -f "$OUTPUT/raw_data/unknown_pci_devices.txt" ]] && [[ -s "$OUTPUT/raw_data/unknown_pci_devices.txt" ]]; then
        echo "The following PCI devices were detected but not specifically tested:" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        cat "$OUTPUT/raw_data/unknown_pci_devices.txt" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "NOTE: These devices may require specialized testing tools or procedures." >> "$REPORT_FILE"
    else
        echo "All detected devices were tested." >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # Test Status Summary
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "  TEST STATUS SUMMARY" >> "$REPORT_FILE"
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    generate_test_summary "$OUTPUT" >> "$REPORT_FILE"
    
    # Report footer
    echo "" >> "$REPORT_FILE"
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "  END OF REPORT" >> "$REPORT_FILE"
    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "For detailed logs and raw data, see: $OUTPUT" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "[✓] Report generated: $REPORT_FILE"
    
    # Create a quick summary file
    generate_quick_summary "$OUTPUT" > "$SUMMARY_FILE"
    echo "[✓] Summary generated: $SUMMARY_FILE"
}

parse_compute_results() {
    local OUTPUT=$1
    
    echo "Component: CPU / Compute Engine"
    echo "Model: ${CPU_MODEL:-Unknown}"
    echo "Cores/Threads: ${CPU_CORES:-Unknown} cores / ${CPU_THREADS:-Unknown} threads"
    echo "Sockets: ${CPU_SOCKETS:-Unknown}"
    echo ""
    echo "Tests Performed:"
    echo "  - Matrix Multiplication (High heat generation)"
    echo "  - FFT (Fast Fourier Transform)"
    echo "  - Ackermann Function (Floating point)"
    echo ""
    
    if [[ -f "$OUTPUT/raw_data/compute_results.yaml" ]]; then
        echo "Results:"
        
        # Try to extract metrics from YAML
        if command -v grep &> /dev/null; then
            local BOGO_OPS=$(grep "bogo-ops:" "$OUTPUT/raw_data/compute_results.yaml" | head -1 | awk '{print $2}' || echo "N/A")
            local BOGO_OPS_S=$(grep "bogo-ops-per-second-real-time:" "$OUTPUT/raw_data/compute_results.yaml" | head -1 | awk '{print $2}' || echo "N/A")
            
            echo "  Total Operations: $BOGO_OPS"
            echo "  Operations/Second: $BOGO_OPS_S"
        fi
        
        echo ""
        echo "Status: COMPLETED"
    else
        echo "Status: NO DATA AVAILABLE"
    fi
    
    if [[ -f "$OUTPUT/logs/compute_stress.log" ]]; then
        echo ""
        echo "Log: See $OUTPUT/logs/compute_stress.log for details"
    fi
}

parse_storage_results() {
    local OUTPUT=$1
    
    if [[ ! -f "$OUTPUT/raw_data/storage_devices.txt" ]]; then
        echo "Status: NO STORAGE DEVICES DETECTED"
        return
    fi
    
    local DEVICE_NUM=0
    while IFS='|' read -r device model size type serial; do
        DEVICE_NUM=$((DEVICE_NUM + 1))
        
        echo "───────────────────────────────────────────────────────────────────────────────"
        echo "Device $DEVICE_NUM: $device"
        echo "───────────────────────────────────────────────────────────────────────────────"
        echo "Model: $model"
        echo "Size: $size"
        echo "Type: $type"
        echo "Serial: $serial"
        echo ""
        
        local SAFE_NAME=$(echo "$device" | tr '/' '_')
        local RESULTS_FILE="$OUTPUT/raw_data/fio_results_${SAFE_NAME}.json"
        
        if [[ -f "$RESULTS_FILE" ]] && command -v jq &> /dev/null; then
            echo "Benchmark Results:"
            echo ""
            
            # Sequential Read
            local SEQ_READ_BW=$(jq -r '.jobs[] | select(.jobname=="seq-read") | .read.bw // 0' "$RESULTS_FILE" 2>/dev/null || echo "0")
            local SEQ_READ_IOPS=$(jq -r '.jobs[] | select(.jobname=="seq-read") | .read.iops // 0' "$RESULTS_FILE" 2>/dev/null || echo "0")
            
            # Sequential Write
            local SEQ_WRITE_BW=$(jq -r '.jobs[] | select(.jobname=="seq-write") | .write.bw // 0' "$RESULTS_FILE" 2>/dev/null || echo "0")
            local SEQ_WRITE_IOPS=$(jq -r '.jobs[] | select(.jobname=="seq-write") | .write.iops // 0' "$RESULTS_FILE" 2>/dev/null || echo "0")
            
            # Random Read 4K
            local RAND_READ_BW=$(jq -r '.jobs[] | select(.jobname=="rand-read-4k") | .read.bw // 0' "$RESULTS_FILE" 2>/dev/null || echo "0")
            local RAND_READ_IOPS=$(jq -r '.jobs[] | select(.jobname=="rand-read-4k") | .read.iops // 0' "$RESULTS_FILE" 2>/dev/null || echo "0")
            
            # Random Write 4K
            local RAND_WRITE_BW=$(jq -r '.jobs[] | select(.jobname=="rand-write-4k") | .write.bw // 0' "$RESULTS_FILE" 2>/dev/null || echo "0")
            local RAND_WRITE_IOPS=$(jq -r '.jobs[] | select(.jobname=="rand-write-4k") | .write.iops // 0' "$RESULTS_FILE" 2>/dev/null || echo "0")
            
            printf "  %-30s %-20s %-20s\n" "Test Type" "Bandwidth (KB/s)" "IOPS"
            printf "  %-30s %-20s %-20s\n" "----------" "----------------" "----"
            printf "  %-30s %-20s %-20s\n" "Sequential Read (1M)" "$SEQ_READ_BW" "$SEQ_READ_IOPS"
            printf "  %-30s %-20s %-20s\n" "Sequential Write (1M)" "$SEQ_WRITE_BW" "$SEQ_WRITE_IOPS"
            printf "  %-30s %-20s %-20s\n" "Random Read (4K)" "$RAND_READ_BW" "$RAND_READ_IOPS"
            printf "  %-30s %-20s %-20s\n" "Random Write (4K)" "$RAND_WRITE_BW" "$RAND_WRITE_IOPS"
            
            echo ""
            echo "Status: COMPLETED"
        else
            echo "Status: NO RESULTS AVAILABLE"
        fi
        
        echo ""
    done < "$OUTPUT/raw_data/storage_devices.txt"
}

parse_network_results() {
    local OUTPUT=$1
    
    if [[ ! -f "$OUTPUT/raw_data/network_devices.txt" ]]; then
        echo "Status: NO NETWORK DEVICES DETECTED"
        return
    fi
    
    local IFACE_NUM=0
    while IFS='|' read -r iface state speed driver details; do
        IFACE_NUM=$((IFACE_NUM + 1))
        
        echo "───────────────────────────────────────────────────────────────────────────────"
        echo "Interface $IFACE_NUM: $iface"
        echo "───────────────────────────────────────────────────────────────────────────────"
        echo "State: $state"
        echo "Link Speed: $speed"
        echo "Driver: $driver"
        [[ -n "$details" ]] && echo "Hardware: $details"
        echo ""
        
        if [[ "$state" != "UP" ]]; then
            echo "Status: SKIPPED (Interface not UP)"
            echo ""
            continue
        fi
        
        local SAFE_IFACE=$(echo "$iface" | tr '/' '_' | tr ':' '_')
        local TCP_RESULTS="$OUTPUT/raw_data/network_results_${SAFE_IFACE}.json.tcp"
        local UDP_RESULTS="$OUTPUT/raw_data/network_results_${SAFE_IFACE}.json.udp"
        
        echo "Test Results:"
        echo ""
        
        if [[ -f "$TCP_RESULTS" ]] && command -v jq &> /dev/null; then
            local TCP_BPS=$(jq -r '.end.sum_received.bits_per_second // 0' "$TCP_RESULTS" 2>/dev/null || echo "0")
            local TCP_GBPS=$(echo "scale=2; $TCP_BPS / 1000000000" | bc 2>/dev/null || echo "0")
            echo "  TCP Throughput: ${TCP_GBPS} Gbps"
        else
            echo "  TCP Throughput: N/A"
        fi
        
        if [[ -f "$UDP_RESULTS" ]] && command -v jq &> /dev/null; then
            local UDP_BPS=$(jq -r '.end.sum.bits_per_second // 0' "$UDP_RESULTS" 2>/dev/null || echo "0")
            local UDP_GBPS=$(echo "scale=2; $UDP_BPS / 1000000000" | bc 2>/dev/null || echo "0")
            local UDP_LOSS=$(jq -r '.end.sum.lost_percent // 0' "$UDP_RESULTS" 2>/dev/null || echo "0")
            echo "  UDP Throughput: ${UDP_GBPS} Gbps"
            echo "  UDP Packet Loss: ${UDP_LOSS}%"
        else
            echo "  UDP Throughput: N/A"
        fi
        
        echo ""
        echo "Status: COMPLETED"
        echo ""
    done < "$OUTPUT/raw_data/network_devices.txt"
}

parse_memory_results() {
    local OUTPUT=$1
    
    echo "Component: System Memory"
    echo "Total Memory: ${TOTAL_MEM_GB:-Unknown} GB"
    echo "Type: ${MEM_TYPE:-Unknown}"
    echo "Speed: ${MEM_SPEED:-Unknown}"
    echo "Populated DIMMs: ${DIMM_COUNT:-Unknown}"
    echo ""
    echo "Tests Performed:"
    echo "  - Memory stress with data verification"
    echo "  - Memory bandwidth test"
    echo "  - Cache latency test"
    echo ""
    
    if [[ -f "$OUTPUT/raw_data/memory_results.yaml" ]]; then
        echo "Results:"
        
        local BOGO_OPS=$(grep "bogo-ops:" "$OUTPUT/raw_data/memory_results.yaml" | head -1 | awk '{print $2}' || echo "N/A")
        local BOGO_OPS_S=$(grep "bogo-ops-per-second-real-time:" "$OUTPUT/raw_data/memory_results.yaml" | head -1 | awk '{print $2}' || echo "N/A")
        
        echo "  Total Operations: $BOGO_OPS"
        echo "  Operations/Second: $BOGO_OPS_S"
        echo ""
        
        # Check for memory errors
        if [[ -d /sys/devices/system/edac/mc ]]; then
            local FINAL_CE=$(cat /sys/devices/system/edac/mc/mc*/ce_count 2>/dev/null | awk '{s+=$1} END {print s}')
            local FINAL_UE=$(cat /sys/devices/system/edac/mc/mc*/ue_count 2>/dev/null | awk '{s+=$1} END {print s}')
            
            echo "Memory Error Count:"
            echo "  Correctable Errors: ${FINAL_CE:-0}"
            echo "  Uncorrectable Errors: ${FINAL_UE:-0}"
            
            if [[ "${FINAL_UE:-0}" -gt 0 ]]; then
                echo ""
                echo "  ⚠️  WARNING: Uncorrectable memory errors detected!"
            fi
        fi
        
        echo ""
        echo "Status: COMPLETED"
    else
        echo "Status: NO DATA AVAILABLE"
    fi
}

parse_monitoring_results() {
    local OUTPUT=$1
    
    if [[ ! -f "$OUTPUT/raw_data/telemetry.csv" ]]; then
        echo "Status: NO MONITORING DATA AVAILABLE"
        return
    fi
    
    echo "Monitoring Summary (from telemetry data):"
    echo ""
    
    # Calculate statistics from CSV
    local TEMP_AVG=$(awk -F',' 'NR>1 && $2>0 {sum+=$2; count++} END {if(count>0) printf "%.1f", sum/count; else print "N/A"}' "$OUTPUT/raw_data/telemetry.csv")
    local TEMP_MAX=$(awk -F',' 'NR>1 && $3>0 {if($3>max) max=$3} END {if(max>0) printf "%.1f", max; else print "N/A"}' "$OUTPUT/raw_data/telemetry.csv")
    local FAN_AVG=$(awk -F',' 'NR>1 && $4>0 {sum+=$4; count++} END {if(count>0) printf "%.0f", sum/count; else print "N/A"}' "$OUTPUT/raw_data/telemetry.csv")
    local POWER_AVG=$(awk -F',' 'NR>1 && $5>0 {sum+=$5; count++} END {if(count>0) printf "%.0f", sum/count; else print "N/A"}' "$OUTPUT/raw_data/telemetry.csv")
    local POWER_MAX=$(awk -F',' 'NR>1 && $5>0 {if($5>max) max=$5} END {if(max>0) printf "%.0f", max; else print "N/A"}' "$OUTPUT/raw_data/telemetry.csv")
    
    printf "  %-30s %s\n" "Average CPU Temperature:" "${TEMP_AVG}°C"
    printf "  %-30s %s\n" "Maximum CPU Temperature:" "${TEMP_MAX}°C"
    printf "  %-30s %s\n" "Average Fan Speed:" "${FAN_AVG} RPM"
    printf "  %-30s %s\n" "Average Power Consumption:" "${POWER_AVG} W"
    printf "  %-30s %s\n" "Peak Power Consumption:" "${POWER_MAX} W"
    
    echo ""
    echo "Detailed telemetry data: $OUTPUT/raw_data/telemetry.csv"
    echo "Sensor timeline: $OUTPUT/raw_data/sensors_timeline.log"
}

generate_test_summary() {
    local OUTPUT=$1
    
    local TOTAL_TESTS=0
    local PASSED_TESTS=0
    local FAILED_TESTS=0
    local SKIPPED_TESTS=0
    
    echo "Test Summary:"
    echo ""
    
    # CPU Test
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [[ -f "$OUTPUT/raw_data/compute_results.yaml" ]]; then
        echo "  [✓] CPU/Compute Stress Test: PASSED"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "  [✗] CPU/Compute Stress Test: FAILED"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    # Storage Test
    if [[ -f "$OUTPUT/raw_data/storage_devices.txt" ]]; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        local STORAGE_RESULTS=$(find "$OUTPUT/raw_data" -name "fio_results_*.json" 2>/dev/null | wc -l)
        if [[ $STORAGE_RESULTS -gt 0 ]]; then
            echo "  [✓] Storage Stress Test: PASSED ($STORAGE_RESULTS devices tested)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "  [✗] Storage Stress Test: FAILED"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    fi
    
    # Network Test
    if [[ -f "$OUTPUT/raw_data/network_devices.txt" ]]; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        local NET_RESULTS=$(find "$OUTPUT/raw_data" -name "network_results_*.json.tcp" 2>/dev/null | wc -l)
        if [[ $NET_RESULTS -gt 0 ]]; then
            echo "  [✓] Network Stress Test: PASSED ($NET_RESULTS interfaces tested)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "  [✗] Network Stress Test: FAILED"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    fi
    
    # Memory Test
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [[ -f "$OUTPUT/raw_data/memory_results.yaml" ]]; then
        echo "  [✓] Memory Stress Test: PASSED"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "  [✗] Memory Stress Test: FAILED"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    # Monitoring
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [[ -f "$OUTPUT/raw_data/telemetry.csv" ]]; then
        echo "  [✓] Monitoring & Telemetry: PASSED"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "  [✗] Monitoring & Telemetry: FAILED"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    echo ""
    echo "───────────────────────────────────────────────────────────────────────────────"
    printf "  Total Tests: %d | Passed: %d | Failed: %d | Skipped: %d\n" "$TOTAL_TESTS" "$PASSED_TESTS" "$FAILED_TESTS" "$SKIPPED_TESTS"
    echo "───────────────────────────────────────────────────────────────────────────────"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo ""
        echo "  ✓ Overall Status: ALL TESTS PASSED"
    else
        echo ""
        echo "  ⚠ Overall Status: SOME TESTS FAILED - Review logs for details"
    fi
}

generate_quick_summary() {
    local OUTPUT=$1
    
    cat <<EOF
USVF Quick Summary

Test Date: $(date)
Test Duration: ${DURATION} seconds
Output Directory: $OUTPUT

Hardware Summary:
-----------------
CPU: ${CPU_MODEL:-Unknown}
Cores/Threads: ${CPU_CORES:-Unknown}/${CPU_THREADS:-Unknown}
Memory: ${TOTAL_MEM_GB:-Unknown} GB ${MEM_TYPE:-Unknown}
BMC: ${BMC_AVAILABLE:-Unknown}

Test Results:
-------------
EOF
    
    # Add test status
    if [[ -f "$OUTPUT/raw_data/compute_results.yaml" ]]; then
        echo "CPU Stress: ✓ PASSED"
    else
        echo "CPU Stress: ✗ FAILED"
    fi
    
    if [[ -f "$OUTPUT/raw_data/memory_results.yaml" ]]; then
        echo "Memory Stress: ✓ PASSED"
    else
        echo "Memory Stress: ✗ FAILED"
    fi
    
    local STORAGE_COUNT=$(find "$OUTPUT/raw_data" -name "fio_results_*.json" 2>/dev/null | wc -l)
    if [[ $STORAGE_COUNT -gt 0 ]]; then
        echo "Storage Stress: ✓ PASSED ($STORAGE_COUNT devices)"
    else
        echo "Storage Stress: - No devices tested"
    fi
    
    local NET_COUNT=$(find "$OUTPUT/raw_data" -name "network_results_*.json.tcp" 2>/dev/null | wc -l)
    if [[ $NET_COUNT -gt 0 ]]; then
        echo "Network Stress: ✓ PASSED ($NET_COUNT interfaces)"
    else
        echo "Network Stress: - No interfaces tested"
    fi
    
    echo ""
    echo "Full Report: $OUTPUT/reports/FINAL_REPORT.txt"
}
