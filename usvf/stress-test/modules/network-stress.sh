#!/bin/bash
# Network Stress Testing Module

start_network_stress() {
    local CORES=$1
    local DURATION=$2
    local OUTPUT=$3
    
    local LOG_FILE="$OUTPUT/logs/network_stress.log"
    local NETWORK_DEVICES_FILE="$OUTPUT/raw_data/network_devices.txt"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Network stress test" | tee "$LOG_FILE"
    echo "Assigned Cores: $CORES" | tee -a "$LOG_FILE"
    echo "Duration: $DURATION seconds" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # Check if network devices were detected
    if [[ ! -f "$NETWORK_DEVICES_FILE" ]]; then
        echo "[!] No network devices file found. Testing loopback only." | tee -a "$LOG_FILE"
        test_network_interface "lo" "Loopback" "Unknown" "Unknown" "" "$CORES" "$DURATION" "$OUTPUT"
        return
    fi
    
    # Test each detected network interface
    local IFACE_COUNT=0
    while IFS='|' read -r iface state speed driver details; do
        IFACE_COUNT=$((IFACE_COUNT + 1))
        
        echo "" | tee -a "$LOG_FILE"
        echo "======================================" | tee -a "$LOG_FILE"
        echo "Testing Interface $IFACE_COUNT: $iface" | tee -a "$LOG_FILE"
        echo "  State: $state" | tee -a "$LOG_FILE"
        echo "  Speed: $speed" | tee -a "$LOG_FILE"
        echo "  Driver: $driver" | tee -a "$LOG_FILE"
        [[ -n "$details" ]] && echo "  Hardware: $details" | tee -a "$LOG_FILE"
        echo "======================================" | tee -a "$LOG_FILE"
        
        # Only test interfaces that are UP
        if [[ "$state" == "UP" ]]; then
            test_network_interface "$iface" "$state" "$speed" "$driver" "$details" "$CORES" "$DURATION" "$OUTPUT"
        else
            echo "[!] Interface $iface is not UP. Skipping." | tee -a "$LOG_FILE"
        fi
        
    done < "$NETWORK_DEVICES_FILE"
    
    echo "" | tee -a "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Network stress test complete" | tee -a "$LOG_FILE"
}

test_network_interface() {
    local IFACE=$1
    local STATE=$2
    local SPEED=$3
    local DRIVER=$4
    local DETAILS=$5
    local CORES=$6
    local DURATION=$7
    local OUTPUT=$8
    
    local LOG_FILE="$OUTPUT/logs/network_stress.log"
    local SAFE_IFACE=$(echo "$IFACE" | tr '/' '_' | tr ':' '_')
    local RESULTS_FILE="$OUTPUT/raw_data/network_results_${SAFE_IFACE}.json"
    
    echo "" | tee -a "$LOG_FILE"
    echo "[→] Testing $IFACE" | tee -a "$LOG_FILE"
    
    # Start iperf3 server on this interface (in background)
    echo "[→] Starting iperf3 server on $IFACE..." | tee -a "$LOG_FILE"
    
    # Determine IP address for this interface
    local IFACE_IP=$(ip -4 addr show "$IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    
    if [[ -z "$IFACE_IP" ]]; then
        echo "[!] No IPv4 address found for $IFACE. Using loopback." | tee -a "$LOG_FILE"
        IFACE_IP="127.0.0.1"
    fi
    
    echo "    Interface IP: $IFACE_IP" | tee -a "$LOG_FILE"
    
    # Start iperf3 server
    local SERVER_PORT=$((5201 + RANDOM % 1000))
    iperf3 -s -p "$SERVER_PORT" -D 2>&1 | tee -a "$LOG_FILE"
    sleep 2
    
    # Run client test - TCP throughput
    echo "[→] Running TCP throughput test (client)..." | tee -a "$LOG_FILE"
    iperf3 -c "$IFACE_IP" -p "$SERVER_PORT" -t "$DURATION" -P "$CORES" -J > "${RESULTS_FILE}.tcp" 2>&1
    
    if [[ -f "${RESULTS_FILE}.tcp" ]]; then
        echo "[✓] TCP test completed" | tee -a "$LOG_FILE"
        
        # Extract results using jq if available
        if command -v jq &> /dev/null; then
            local TCP_THROUGHPUT=$(jq -r '.end.sum_received.bits_per_second // 0' "${RESULTS_FILE}.tcp" 2>/dev/null)
            if [[ -n "$TCP_THROUGHPUT" ]] && [[ "$TCP_THROUGHPUT" != "0" ]]; then
                local TCP_GBPS=$(echo "scale=2; $TCP_THROUGHPUT / 1000000000" | bc)
                echo "    TCP Throughput: ${TCP_GBPS} Gbps" | tee -a "$LOG_FILE"
            fi
        fi
    fi
    
    sleep 2
    
    # Run UDP test
    echo "[→] Running UDP throughput test..." | tee -a "$LOG_FILE"
    iperf3 -c "$IFACE_IP" -p "$SERVER_PORT" -t $((DURATION / 2)) -u -b 10G -J > "${RESULTS_FILE}.udp" 2>&1
    
    if [[ -f "${RESULTS_FILE}.udp" ]]; then
        echo "[✓] UDP test completed" | tee -a "$LOG_FILE"
        
        if command -v jq &> /dev/null; then
            local UDP_THROUGHPUT=$(jq -r '.end.sum.bits_per_second // 0' "${RESULTS_FILE}.udp" 2>/dev/null)
            local UDP_LOSS=$(jq -r '.end.sum.lost_percent // 0' "${RESULTS_FILE}.udp" 2>/dev/null)
            
            if [[ -n "$UDP_THROUGHPUT" ]] && [[ "$UDP_THROUGHPUT" != "0" ]]; then
                local UDP_GBPS=$(echo "scale=2; $UDP_THROUGHPUT / 1000000000" | bc)
                echo "    UDP Throughput: ${UDP_GBPS} Gbps" | tee -a "$LOG_FILE"
                echo "    UDP Packet Loss: ${UDP_LOSS}%" | tee -a "$LOG_FILE"
            fi
        fi
    fi
    
    # Kill iperf3 server
    pkill -f "iperf3 -s -p $SERVER_PORT" 2>/dev/null || true
    
    # Collect interface statistics
    echo "[→] Collecting interface statistics..." | tee -a "$LOG_FILE"
    ip -s link show "$IFACE" > "$OUTPUT/raw_data/ifstats_${SAFE_IFACE}.txt"
    ethtool -S "$IFACE" > "$OUTPUT/raw_data/ethtool_stats_${SAFE_IFACE}.txt" 2>/dev/null || true
    
    echo "" | tee -a "$LOG_FILE"
}
