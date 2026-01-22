#!/bin/bash
################################################################################
# Deployment Verification Module
#
# Verifies the complete virtual DC deployment:
# - VM status and accessibility
# - Network connectivity
# - BGP session status
# - Route propagation
################################################################################

verify_deployment() {
    local config_file="$1"

    log_info "Starting deployment verification..."

    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local ssh_key=$(get_vdc_ssh_private_key "$dc_name")

    # Verify VMs
    verify_vms "$config_file"

    # Verify network connectivity
    verify_network_connectivity "$config_file" "$ssh_key"

    # Verify BGP sessions
    verify_bgp_sessions "$config_file" "$ssh_key"

    # Generate verification report
    generate_verification_report "$config_file" "$ssh_key"

    log_success "Deployment verification completed"
}

verify_vms() {
    local config_file="$1"
    
    log_info "Verifying VM status..."
    
    local hv_count=$(yq eval '.hypervisors | length' "$config_file")
    local total_switches=0
    
    # Count switches
    for tier in leaf spine superspine; do
        local count=$(yq eval ".switches.$tier | length" "$config_file")
        total_switches=$((total_switches + count))
    done
    
    local expected_vms=$((hv_count + total_switches))
    local running_vms=$(virsh list --name | wc -l)
    
    log_info "Expected VMs: $expected_vms"
    log_info "Running VMs: $running_vms"
    
    # List all VMs
    log_info "VM Status:"
    virsh list --all
    
    if [[ $running_vms -lt $expected_vms ]]; then
        log_warn "Not all VMs are running"
        return 1
    fi
    
    log_success "✓ All VMs are running"
}

verify_network_connectivity() {
    local config_file="$1"
    local ssh_key="$2"
    
    log_info "Verifying network connectivity..."
    
    local hv_count=$(yq eval '.hypervisors | length' "$config_file")
    local reachable=0
    local unreachable=0
    
    for i in $(seq 0 $((hv_count - 1))); do
        local hv_name=$(yq eval ".hypervisors[$i].name" "$config_file")
        local mgmt_ip=$(yq eval ".hypervisors[$i].management.ip" "$config_file" | cut -d'/' -f1)
        
        log_info "Checking connectivity to $hv_name ($mgmt_ip)..."
        
        if ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
               -o ConnectTimeout=5 "ubuntu@${mgmt_ip}" "echo connected" &>/dev/null; then
            log_success "✓ $hv_name is reachable"
            reachable=$((reachable + 1))
        else
            log_error "✗ $hv_name is not reachable"
            unreachable=$((unreachable + 1))
        fi
    done
    
    log_info "Reachable: $reachable/$hv_count hypervisors"
    
    if [[ $unreachable -gt 0 ]]; then
        log_warn "$unreachable hypervisors are not reachable"
        return 1
    fi
    
    log_success "✓ All hypervisors are reachable"
}

verify_bgp_sessions() {
    local config_file="$1"
    local ssh_key="$2"
    
    log_info "Verifying BGP sessions..."
    
    local hv_count=$(yq eval '.hypervisors | length' "$config_file")
    
    for i in $(seq 0 $((hv_count - 1))); do
        local hv_name=$(yq eval ".hypervisors[$i].name" "$config_file")
        local mgmt_ip=$(yq eval ".hypervisors[$i].management.ip" "$config_file" | cut -d'/' -f1)
        
        log_info "Checking BGP status on $hv_name..."
        
        # Check if FRR is running
        if ! ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                "ubuntu@${mgmt_ip}" "sudo systemctl is-active frr" &>/dev/null; then
            log_warn "FRR is not running on $hv_name"
            continue
        fi
        
        # Get BGP summary
        log_info "BGP Summary for $hv_name:"
        ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "ubuntu@${mgmt_ip}" "sudo vtysh -c 'show bgp summary'" 2>/dev/null || \
            log_warn "Could not retrieve BGP summary from $hv_name"
        
        echo
    done
    
    log_success "✓ BGP verification completed"
}

generate_verification_report() {
    local config_file="$1"
    local ssh_key="$2"
    
    local report_file="$PROJECT_ROOT/config/verification-report.txt"
    
    log_info "Generating verification report: $report_file"
    
    {
        echo "════════════════════════════════════════════════════════════════"
        echo "         Virtual DC Deployment Verification Report"
        echo "════════════════════════════════════════════════════════════════"
        echo "Generated: $(date)"
        echo "Config File: $config_file"
        echo ""
        
        echo "─────────────────────────────────────────────────────────────────"
        echo "VM Status"
        echo "─────────────────────────────────────────────────────────────────"
        virsh list --all
        echo ""
        
        echo "─────────────────────────────────────────────────────────────────"
        echo "Network Status"
        echo "─────────────────────────────────────────────────────────────────"
        virsh net-list --all
        echo ""
        
        echo "─────────────────────────────────────────────────────────────────"
        echo "Hypervisor Details"
        echo "─────────────────────────────────────────────────────────────────"
        
        local hv_count=$(yq eval '.hypervisors | length' "$config_file")
        for i in $(seq 0 $((hv_count - 1))); do
            local hv_name=$(yq eval ".hypervisors[$i].name" "$config_file")
            local router_id=$(yq eval ".hypervisors[$i].router_id" "$config_file")
            local asn=$(yq eval ".hypervisors[$i].asn" "$config_file")
            local mgmt_ip=$(yq eval ".hypervisors[$i].management.ip" "$config_file")
            
            echo "Hypervisor: $hv_name"
            echo "  Router ID: $router_id"
            echo "  ASN: $asn"
            echo "  Management IP: $mgmt_ip"
            echo ""
        done
        
        echo "─────────────────────────────────────────────────────────────────"
        echo "Switch Details"
        echo "─────────────────────────────────────────────────────────────────"
        
        for tier in leaf spine superspine; do
            local count=$(yq eval ".switches.$tier | length" "$config_file")
            if [[ $count -gt 0 ]]; then
                echo "${tier^} Switches:"
                for i in $(seq 0 $((count - 1))); do
                    local sw_name=$(yq eval ".switches.$tier[$i].name" "$config_file")
                    local router_id=$(yq eval ".switches.$tier[$i].router_id" "$config_file")
                    local asn=$(yq eval ".switches.$tier[$i].asn" "$config_file")
                    local mgmt_ip=$(yq eval ".switches.$tier[$i].management.ip" "$config_file")
                    
                    echo "  - $sw_name (Router ID: $router_id, ASN: $asn, IP: $mgmt_ip)"
                done
                echo ""
            fi
        done
        
        echo "════════════════════════════════════════════════════════════════"
    } > "$report_file"
    
    cat "$report_file"
    
    log_success "✓ Verification report generated: $report_file"
}

verify_bgp_routes() {
    local device_name="$1"
    local mgmt_ip="$2"
    local ssh_key="$3"
    
    log_info "Verifying BGP routes on $device_name..."
    
    ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "ubuntu@${mgmt_ip}" "sudo vtysh -c 'show bgp ipv4 unicast'" 2>/dev/null
}

verify_interface_status() {
    local device_name="$1"
    local mgmt_ip="$2"
    local ssh_key="$3"
    
    log_info "Verifying interface status on $device_name..."
    
    ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "ubuntu@${mgmt_ip}" "ip link show" 2>/dev/null
}

test_connectivity() {
    local src_vm="$1"
    local src_ip="$2"
    local dst_ip="$3"
    local ssh_key="$4"
    
    log_info "Testing connectivity from $src_vm to $dst_ip..."
    
    if ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           "ubuntu@${src_ip}" "ping -c 3 $dst_ip" &>/dev/null; then
        log_success "✓ Connectivity successful"
        return 0
    else
        log_error "✗ Connectivity failed"
        return 1
    fi
}
