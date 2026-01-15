#!/bin/bash
# Network Telemetry Module
# Collects comprehensive network metrics including bandwidth, errors, drops, temperature, link status, queue stats

collect_network_telemetry() {
    if [[ "$ENABLE_NETWORK_TELEMETRY" != "true" ]]; then
        return
    fi
    
    local telemetry_data=""
    local json_data="{"
    
    log_message "INFO" "Collecting Network telemetry..."
    
    # Get all network interfaces
    local interfaces=$(detect_network_interfaces)
    
    if [[ -z "$interfaces" ]]; then
        telemetry_data+="No network interfaces detected\n"
        json_data+="\"interfaces\": []}"
        log_telemetry "Network" "$telemetry_data"
        json_add_module "network" "$json_data"
        return
    fi
    
    json_data+="\"interfaces\": ["
    local if_count=0
    
    while IFS= read -r iface; do
        [[ -z "$iface" ]] && continue
        
        [[ $if_count -gt 0 ]] && json_data+=","
        
        telemetry_data+="\n=== Interface: $iface ===\n"
        json_data+="{\"interface\": \"$iface\","
        
        # === Basic Interface Information ===
        local mac_addr=$(ip link show "$iface" 2>/dev/null | grep -o "link/ether [0-9a-f:]*" | awk '{print $2}' || echo "Unknown")
        local state=$(ip link show "$iface" 2>/dev/null | grep -o "state [A-Z]*" | awk '{print $2}' || echo "Unknown")
        local mtu=$(ip link show "$iface" 2>/dev/null | grep -o "mtu [0-9]*" | awk '{print $2}' || echo "Unknown")
        
        telemetry_data+="MAC Address: $mac_addr\n"
        telemetry_data+="State: $state\n"
        telemetry_data+="MTU: $mtu\n"
        
        json_data+="\"mac_address\": \"$mac_addr\","
        json_data+="\"state\": \"$state\","
        json_data+="\"mtu\": $mtu,"
        
        # IP Addresses
        local ipv4=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || echo "")
        local ipv6=$(ip -6 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet6\s)[0-9a-f:]+' | head -1 || echo "")
        
        if [[ -n "$ipv4" ]]; then
            telemetry_data+="IPv4: $ipv4\n"
            json_data+="\"ipv4\": \"$ipv4\","
        else
            json_data+="\"ipv4\": null,"
        fi
        
        if [[ -n "$ipv6" ]]; then
            telemetry_data+="IPv6: $ipv6\n"
            json_data+="\"ipv6\": \"$ipv6\","
        else
            json_data+="\"ipv6\": null,"
        fi
        
        # === Driver Information ===
        if command_exists ethtool; then
            local driver=$(ethtool -i "$iface" 2>/dev/null | grep "^driver:" | awk '{print $2}' || echo "Unknown")
            local version=$(ethtool -i "$iface" 2>/dev/null | grep "^version:" | awk '{print $2}' || echo "Unknown")
            local firmware=$(ethtool -i "$iface" 2>/dev/null | grep "^firmware-version:" | awk '{print $2}' || echo "Unknown")
            local bus_info=$(ethtool -i "$iface" 2>/dev/null | grep "^bus-info:" | awk '{print $2}' || echo "Unknown")
            
            telemetry_data+="Driver: $driver\n"
            telemetry_data+="Version: $version\n"
            telemetry_data+="Firmware: $firmware\n"
            telemetry_data+="Bus Info: $bus_info\n"
            
            json_data+="\"driver\": \"$driver\","
            json_data+="\"driver_version\": \"$version\","
            json_data+="\"firmware_version\": \"$firmware\","
            json_data+="\"bus_info\": \"$bus_info\","
        fi
        
        # === Link Status ===
        if [[ "$NETWORK_COLLECT_LINK_STATUS" == "true" ]] && command_exists ethtool; then
            telemetry_data+="\n--- Link Status ---\n"
            
            local link_detected=$(ethtool "$iface" 2>/dev/null | grep "Link detected:" | awk '{print $3}' || echo "unknown")
            local speed=$(ethtool "$iface" 2>/dev/null | grep "Speed:" | awk '{print $2}' || echo "Unknown")
            local duplex=$(ethtool "$iface" 2>/dev/null | grep "Duplex:" | awk '{print $2}' || echo "Unknown")
            local auto_neg=$(ethtool "$iface" 2>/dev/null | grep "Auto-negotiation:" | awk '{print $2}' || echo "Unknown")
            
            telemetry_data+="Link Detected: $link_detected\n"
            telemetry_data+="Speed: $speed\n"
            telemetry_data+="Duplex: $duplex\n"
            telemetry_data+="Auto-negotiation: $auto_neg\n"
            
            json_data+="\"link_detected\": \"$link_detected\","
            json_data+="\"speed\": \"$speed\","
            json_data+="\"duplex\": \"$duplex\","
            json_data+="\"auto_negotiation\": \"$auto_neg\","
        fi
        
        # === Bandwidth and Traffic ===
        if [[ "$NETWORK_COLLECT_BANDWIDTH" == "true" ]]; then
            telemetry_data+="\n--- Bandwidth Statistics ---\n"
            
            local rx_bytes=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo "0")
            local tx_bytes=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo "0")
            local rx_packets=$(cat /sys/class/net/$iface/statistics/rx_packets 2>/dev/null || echo "0")
            local tx_packets=$(cat /sys/class/net/$iface/statistics/tx_packets 2>/dev/null || echo "0")
            
            local rx_human=$(format_bytes $rx_bytes)
            local tx_human=$(format_bytes $tx_bytes)
            
            telemetry_data+="RX Bytes: $rx_human\n"
            telemetry_data+="TX Bytes: $tx_human\n"
            telemetry_data+="RX Packets: $rx_packets\n"
            telemetry_data+="TX Packets: $tx_packets\n"
            
            json_data+="\"rx_bytes\": $rx_bytes,"
            json_data+="\"tx_bytes\": $tx_bytes,"
            json_data+="\"rx_packets\": $rx_packets,"
            json_data+="\"tx_packets\": $tx_packets,"
            
            # Current bandwidth if sar is available
            if command_exists sar; then
                local bandwidth=$(sar -n DEV 1 1 2>/dev/null | grep "$iface" | grep -v "Average" | tail -1)
                if [[ -n "$bandwidth" ]]; then
                    local rxkB=$(echo "$bandwidth" | awk '{print $5}')
                    local txkB=$(echo "$bandwidth" | awk '{print $6}')
                    telemetry_data+="Current RX Rate: ${rxkB}kB/s\n"
                    telemetry_data+="Current TX Rate: ${txkB}kB/s\n"
                fi
            fi
        fi
        
        # === Errors and Drops ===
        if [[ "$NETWORK_COLLECT_ERRORS" == "true" ]] || [[ "$NETWORK_COLLECT_DROPS" == "true" ]]; then
            telemetry_data+="\n--- Errors and Drops ---\n"
            
            local rx_errors=$(cat /sys/class/net/$iface/statistics/rx_errors 2>/dev/null || echo "0")
            local tx_errors=$(cat /sys/class/net/$iface/statistics/tx_errors 2>/dev/null || echo "0")
            local rx_dropped=$(cat /sys/class/net/$iface/statistics/rx_dropped 2>/dev/null || echo "0")
            local tx_dropped=$(cat /sys/class/net/$iface/statistics/tx_dropped 2>/dev/null || echo "0")
            local collisions=$(cat /sys/class/net/$iface/statistics/collisions 2>/dev/null || echo "0")
            local rx_crc_errors=$(cat /sys/class/net/$iface/statistics/rx_crc_errors 2>/dev/null || echo "0")
            local rx_frame_errors=$(cat /sys/class/net/$iface/statistics/rx_frame_errors 2>/dev/null || echo "0")
            local rx_fifo_errors=$(cat /sys/class/net/$iface/statistics/rx_fifo_errors 2>/dev/null || echo "0")
            local tx_fifo_errors=$(cat /sys/class/net/$iface/statistics/tx_fifo_errors 2>/dev/null || echo "0")
            
            telemetry_data+="RX Errors: $rx_errors\n"
            telemetry_data+="TX Errors: $tx_errors\n"
            telemetry_data+="RX Dropped: $rx_dropped\n"
            telemetry_data+="TX Dropped: $tx_dropped\n"
            telemetry_data+="Collisions: $collisions\n"
            telemetry_data+="RX CRC Errors: $rx_crc_errors\n"
            telemetry_data+="RX Frame Errors: $rx_frame_errors\n"
            telemetry_data+="RX FIFO Errors: $rx_fifo_errors\n"
            telemetry_data+="TX FIFO Errors: $tx_fifo_errors\n"
            
            json_data+="\"rx_errors\": $rx_errors,"
            json_data+="\"tx_errors\": $tx_errors,"
            json_data+="\"rx_dropped\": $rx_dropped,"
            json_data+="\"tx_dropped\": $tx_dropped,"
            json_data+="\"collisions\": $collisions,"
            json_data+="\"rx_crc_errors\": $rx_crc_errors,"
            json_data+="\"rx_frame_errors\": $rx_frame_errors,"
            json_data+="\"rx_fifo_errors\": $rx_fifo_errors,"
            json_data+="\"tx_fifo_errors\": $tx_fifo_errors,"
            
            # Alert on high error/drop rates
            if [[ "$NETWORK_COLLECT_ERRORS" == "true" ]]; then
                local total_errors=$((rx_errors + tx_errors))
                if [[ $total_errors -gt $ALERT_NETWORK_ERRORS_THRESHOLD ]]; then
                    telemetry_data+="WARNING: High error count ($total_errors)!\n"
                fi
            fi
            
            if [[ "$NETWORK_COLLECT_DROPS" == "true" ]]; then
                local total_drops=$((rx_dropped + tx_dropped))
                if [[ $total_drops -gt $ALERT_NETWORK_DROPS_THRESHOLD ]]; then
                    telemetry_data+="WARNING: High drop count ($total_drops)!\n"
                fi
            fi
        fi
        
        # === Queue Statistics ===
        if [[ "$NETWORK_COLLECT_QUEUE_STATS" == "true" ]] && command_exists ethtool; then
            telemetry_data+="\n--- Queue Statistics ---\n"
            
            # Ring buffer settings
            local ring_stats=$(ethtool -g "$iface" 2>/dev/null)
            if [[ -n "$ring_stats" ]]; then
                local rx_ring=$(echo "$ring_stats" | grep "^RX:" | tail -1 | awk '{print $2}')
                local tx_ring=$(echo "$ring_stats" | grep "^TX:" | tail -1 | awk '{print $2}')
                
                if [[ -n "$rx_ring" ]]; then
                    telemetry_data+="RX Ring Buffer: $rx_ring\n"
                    json_data+="\"rx_ring_buffer\": $rx_ring,"
                fi
                
                if [[ -n "$tx_ring" ]]; then
                    telemetry_data+="TX Ring Buffer: $tx_ring\n"
                    json_data+="\"tx_ring_buffer\": $tx_ring,"
                fi
            fi
            
            # Queue statistics
            local queue_stats=$(ethtool -S "$iface" 2>/dev/null | head -20)
            if [[ -n "$queue_stats" ]]; then
                telemetry_data+="Queue Stats (sample):\n$queue_stats\n"
            fi
        fi
        
        # === Temperature (if available) ===
        if [[ "$NETWORK_COLLECT_TEMPERATURE" == "true" ]]; then
            telemetry_data+="\n--- Temperature ---\n"
            
            local temp_found=false
            
            # Try sensors for NIC temperature
            if command_exists sensors; then
                local nic_temp=$(sensors 2>/dev/null | grep -i "$iface\|network\|nic" | grep "°C" | head -1)
                if [[ -n "$nic_temp" ]]; then
                    telemetry_data+="$nic_temp\n"
                    temp_found=true
                    
                    local temp_value=$(echo "$nic_temp" | grep -oP '\+\K[0-9.]+' | head -1)
                    if [[ -n "$temp_value" ]]; then
                        json_data+="\"temperature_celsius\": $temp_value,"
                    fi
                fi
            fi
            
            # Try ethtool module info
            if [[ "$temp_found" == "false" ]] && command_exists ethtool; then
                local module_info=$(ethtool -m "$iface" 2>/dev/null | grep -i "temperature")
                if [[ -n "$module_info" ]]; then
                    telemetry_data+="$module_info\n"
                    temp_found=true
                fi
            fi
            
            if [[ "$temp_found" == "false" ]]; then
                telemetry_data+="Temperature: Not available\n"
                json_data+="\"temperature_celsius\": null,"
            fi
        fi
        
        # === Offload Features ===
        if command_exists ethtool; then
            telemetry_data+="\n--- Offload Features ---\n"
            
            local tso=$(ethtool -k "$iface" 2>/dev/null | grep "tcp-segmentation-offload:" | awk '{print $2}')
            local gso=$(ethtool -k "$iface" 2>/dev/null | grep "generic-segmentation-offload:" | awk '{print $2}')
            local gro=$(ethtool -k "$iface" 2>/dev/null | grep "generic-receive-offload:" | awk '{print $2}')
            local rx_csum=$(ethtool -k "$iface" 2>/dev/null | grep "rx-checksumming:" | awk '{print $2}')
            local tx_csum=$(ethtool -k "$iface" 2>/dev/null | grep "tx-checksumming:" | awk '{print $2}')
            
            if [[ -n "$tso" ]]; then
                telemetry_data+="TSO: $tso\n"
                json_data+="\"tso\": \"$tso\","
            fi
            
            if [[ -n "$gso" ]]; then
                telemetry_data+="GSO: $gso\n"
                json_data+="\"gso\": \"$gso\","
            fi
            
            if [[ -n "$gro" ]]; then
                telemetry_data+="GRO: $gro\n"
                json_data+="\"gro\": \"$gro\","
            fi
        fi
        
        # === PCI Device Information (if applicable) ===
        if command_exists ethtool; then
            local bus_info=$(ethtool -i "$iface" 2>/dev/null | grep "^bus-info:" | awk '{print $2}')
            if [[ -n "$bus_info" ]] && [[ "$bus_info" != "Unknown" ]]; then
                local pci_info=$(lspci -s "$bus_info" 2>/dev/null | cut -d: -f3-)
                if [[ -n "$pci_info" ]]; then
                    telemetry_data+="\n--- Hardware ---\n"
                    telemetry_data+="PCI Device: $pci_info\n"
                    json_data+="\"pci_device\": \"$pci_info\","
                fi
            fi
        fi
        
        # === Connection Tracking (if interface is active) ===
        if [[ "$state" == "UP" ]]; then
            local connections=$(ss -s 2>/dev/null)
            if [[ -n "$connections" ]]; then
                telemetry_data+="\n--- Connection Summary ---\n"
                telemetry_data+="$connections\n"
            fi
        fi
        
        # Close interface JSON
        json_data="${json_data%,}}"
        ((if_count++))
        
    done <<< "$interfaces"
    
    # Close JSON array
    json_data+="],"
    
    # === Network Summary ===
    telemetry_data+="\n=== Network Summary ===\n"
    telemetry_data+="Total Interfaces: $if_count\n"
    
    # Active connections
    if command_exists ss; then
        local tcp_connections=$(ss -t 2>/dev/null | grep -c "ESTAB" || echo "0")
        local udp_connections=$(ss -u 2>/dev/null | wc -l || echo "0")
        
        telemetry_data+="Active TCP Connections: $tcp_connections\n"
        telemetry_data+="Active UDP Connections: $udp_connections\n"
        
        json_data+="\"summary\": {"
        json_data+="\"total_interfaces\": $if_count,"
        json_data+="\"tcp_connections\": $tcp_connections,"
        json_data+="\"udp_connections\": $udp_connections"
        json_data+="}"
    fi
    
    # Close JSON
    json_data+="}"
    
    # Log the telemetry
    log_telemetry "Network" "$telemetry_data"
    
    # Add to JSON output
    json_add_module "network" "$json_data"
    
    log_message "INFO" "Network telemetry collection complete"
}

# Export function
export -f collect_network_telemetry
