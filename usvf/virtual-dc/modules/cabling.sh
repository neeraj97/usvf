#!/bin/bash
################################################################################
# Cabling Configuration Module
#
# Configures virtual network connections between devices:
# - Point-to-point links between hypervisors and switches
# - Inter-switch links (leaf-spine, spine-superspine)
# - UDP sockets or veth pairs for VM interconnection
################################################################################

configure_cabling() {
    local config_file="$1"
    local dry_run="${2:-false}"
    
    log_info "Configuring virtual cabling (L3 data plane)..."
    
    local cable_count=$(yq eval '.cabling | length' "$config_file")
    
    log_info "Total cable connections to configure: $cable_count"
    
    # Configure each cable connection
    for i in $(seq 0 $((cable_count - 1))); do
        configure_single_cable "$config_file" "$i" "$dry_run"
    done
    
    log_success "Virtual cabling configuration completed"
}

configure_single_cable() {
    local config_file="$1"
    local index="$2"
    local dry_run="$3"
    
    local src_device=$(yq eval ".cabling[$index].source.device" "$config_file")
    local src_iface=$(yq eval ".cabling[$index].source.interface" "$config_file")
    local dst_device=$(yq eval ".cabling[$index].destination.device" "$config_file")
    local dst_iface=$(yq eval ".cabling[$index].destination.interface" "$config_file")
    local description=$(yq eval ".cabling[$index].description" "$config_file")
    
    log_info "Cable $index: $src_device:$src_iface <-> $dst_device:$dst_iface"
    log_info "  Description: $description"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would create cable connection"
        return 0
    fi
    
    # Create virtual network for this P2P link
    create_p2p_network "$config_file" "$src_device" "$src_iface" "$dst_device" "$dst_iface" "$index"
    
    # Attach interfaces to VMs
    attach_interface_to_vm "$config_file" "$src_device" "$src_iface" "$index"
    attach_interface_to_vm "$config_file" "$dst_device" "$dst_iface" "$index"
    
    log_success "✓ Cable connection configured"
}

create_p2p_network() {
    local config_file="$1"
    local src_device="$2"
    local src_iface="$3"
    local dst_device="$4"
    local dst_iface="$5"
    local link_id="$6"
    
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local network_name="${dc_name}-p2p-link-${link_id}"
    local network_xml=$(get_vdc_network_xml "$dc_name" "${network_name}")
    
    log_info "Creating P2P network: $network_name"
    
    # Create isolated network for this P2P link
    cat > "$network_xml" <<EOF
<network>
  <name>$network_name</name>
  <forward mode='none'/>
  <bridge name='virbr-${dc_name}-p2p-${link_id}' stp='off' delay='0'/>
</network>
EOF
    
    # Check if network already exists
    if virsh net-list --all | grep -q "$network_name"; then
        log_info "Network $network_name already exists"
        return 0
    fi
    
    # Define and start network
    virsh net-define "$network_xml"
    virsh net-start "$network_name"
    virsh net-autostart "$network_name"
    
    log_success "✓ P2P network $network_name created"
}

attach_interface_to_vm() {
    local config_file="$1"
    local vm_name="$2"
    local iface_name="$3"
    local link_id="$4"
    
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local network_name="${dc_name}-p2p-link-${link_id}"
    local full_vm_name="${dc_name}-${vm_name}"
    
    log_info "Attaching interface to $full_vm_name on network $network_name"
    
    # Check if VM exists
    if ! virsh list --all --name | grep -q "^${full_vm_name}$"; then
        log_warn "VM $full_vm_name not found, skipping interface attachment"
        return 1
    fi
    
    # Attach network interface to VM
    # Note: The interface will appear as ethX in the VM
    # We'll need to configure it post-boot
    
    virsh attach-interface "$full_vm_name" \
        --type network \
        --source "$network_name" \
        --model virtio \
        --config \
        --persistent 2>/dev/null || log_warn "Could not attach interface (VM may need to be running)"
    
    log_success "✓ Interface attached to $full_vm_name"
}

configure_interface_in_vm() {
    local vm_name="$1"
    local iface_name="$2"
    local mgmt_ip="$3"
    local ssh_key="$4"
    
    log_info "Configuring interface $iface_name in $vm_name..."
    
    # Configure the interface for IPv6 link-local (for BGP unnumbered)
    ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "ubuntu@${mgmt_ip}" <<ENDSSH 2>/dev/null
sudo ip link set $iface_name up
sudo ip -6 addr add fe80::1/64 dev $iface_name
sudo sysctl -w net.ipv6.conf.${iface_name}.disable_ipv6=0
ENDSSH
    
    log_success "✓ Interface $iface_name configured in $vm_name"
}

verify_cabling() {
    local config_file="$1"
    
    log_info "Verifying cable connections..."
    
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local cable_count=$(yq eval '.cabling | length' "$config_file")
    local verified=0
    local failed=0
    
    for i in $(seq 0 $((cable_count - 1))); do
        local network_name="${dc_name}-p2p-link-${i}"
        
        if virsh net-list --all | grep -q "$network_name"; then
            verified=$((verified + 1))
        else
            log_warn "Network $network_name not found"
            failed=$((failed + 1))
        fi
    done
    
    log_info "Verified: $verified/$cable_count cable connections"
    
    if [[ $failed -gt 0 ]]; then
        log_warn "$failed cable connections could not be verified"
        return 1
    fi
    
    log_success "✓ All cable connections verified"
    return 0
}

cleanup_cabling() {
    local config_file="$1"
    
    log_info "Cleaning up cable connections..."
    
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local cable_count=$(yq eval '.cabling | length' "$config_file")
    
    for i in $(seq 0 $((cable_count - 1))); do
        local network_name="${dc_name}-p2p-link-${i}"
        
        if virsh net-list --all | grep -q "$network_name"; then
            virsh net-destroy "$network_name" 2>/dev/null || true
            virsh net-undefine "$network_name" 2>/dev/null || true
            log_info "✓ Removed $network_name"
        fi
        
        # Remove network XML file
        local network_xml=$(get_vdc_network_xml "$dc_name" "${network_name}")
        if [[ -f "$network_xml" ]]; then
            rm -f "$network_xml"
        fi
    done
    
    log_success "Cable connections cleaned up"
}

show_network_topology() {
    local config_file="$1"
    
    log_info "Network Topology:"
    echo
    
    # Display the visual topology from config
    yq eval '.topology_visual' "$config_file"
    
    echo
    log_info "Active Networks:"
    virsh net-list --all
    
    echo
    log_info "Active VMs:"
    virsh list --all
}
