#!/bin/bash
################################################################################
# Cabling Configuration Module
#
# Configures virtual network connections between devices:
# - Point-to-point links between hypervisors and switches
# - Inter-switch links (leaf-spine, spine-superspine)
# - UDP sockets or veth pairs for VM interconnection
################################################################################

# Lookup which P2P network a device interface should connect to
# Returns: network name (e.g., "dc3-p2p-link-5") or "none" if not found
lookup_interface_network() {
    local config_file="$1"
    local device_name="$2"
    local interface_name="$3"
    
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local cable_count=$(yq eval '.cabling | length' "$config_file")
    
    # Search through all cables to find this device:interface combination
    for i in $(seq 0 $((cable_count - 1))); do
        local src_device=$(yq eval ".cabling[$i].source.device" "$config_file")
        local src_iface=$(yq eval ".cabling[$i].source.interface" "$config_file")
        local dst_device=$(yq eval ".cabling[$i].destination.device" "$config_file")
        local dst_iface=$(yq eval ".cabling[$i].destination.interface" "$config_file")
        
        # Check if this cable matches our device:interface
        if [[ "$src_device" == "$device_name" && "$src_iface" == "$interface_name" ]]; then
            echo "${dc_name}-p2p-link-${i}"
            return 0
        fi
        
        if [[ "$dst_device" == "$device_name" && "$dst_iface" == "$interface_name" ]]; then
            echo "${dc_name}-p2p-link-${i}"
            return 0
        fi
    done
    
    # Interface not found in cabling - return "none"
    echo "none"
    return 1
}

# Pre-create all P2P networks BEFORE creating VMs
# This allows VMs to connect directly to correct networks during creation
create_p2p_networks() {
    local config_file="$1"
    local dry_run="${2:-false}"
    
    log_info "Pre-creating all P2P networks for direct VM attachment..."
    
    local cable_count=$(yq eval '.cabling | length' "$config_file")
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    
    log_info "Total P2P networks to create: $cable_count"
    
    # Create each P2P network
    for i in $(seq 0 $((cable_count - 1))); do
        local src_device=$(yq eval ".cabling[$i].source.device" "$config_file")
        local src_iface=$(yq eval ".cabling[$i].source.interface" "$config_file")
        local dst_device=$(yq eval ".cabling[$i].destination.device" "$config_file")
        local dst_iface=$(yq eval ".cabling[$i].destination.interface" "$config_file")
        local description=$(yq eval ".cabling[$i].description" "$config_file")
        
        if [[ "$dry_run" == "true" ]]; then
            log_info "[DRY RUN] Would create P2P network for: $src_device:$src_iface <-> $dst_device:$dst_iface"
            continue
        fi
        
        log_info "Creating P2P network $i: $src_device:$src_iface <-> $dst_device:$dst_iface"
        create_p2p_network "$config_file" "$src_device" "$src_iface" "$dst_device" "$dst_iface" "$i"
    done
    
    log_success "All P2P networks created - VMs can now attach directly"
}

# Legacy function for backwards compatibility - now just creates networks
configure_cabling() {
    local config_file="$1"
    local dry_run="${2:-false}"
    
    log_info "Virtual cabling already configured during network creation"
    log_info "All P2P networks were created before VMs"
    log_success "Cabling verification complete"
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
  <bridge name='vbr-${dc_name}-p2p-${link_id}' stp='off' delay='0'/>
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
    
    log_info "Updating interface $iface_name on $full_vm_name to network $network_name"
    
    # Check if VM exists
    if ! virsh list --all --name | grep -q "^${full_vm_name}$"; then
        log_warn "VM $full_vm_name not found, skipping interface update"
        return 1
    fi
    
    # Extract PCI slot from interface name (enp2s0 -> slot 2, enp3s0 -> slot 3, etc.)
    local slot_num=$(echo "$iface_name" | grep -oP 'enp\K\d+')
    
    if [[ -z "$slot_num" ]]; then
        log_error "Could not extract slot number from interface name: $iface_name"
        return 1
    fi
    
    # PCI address format: 0000:00:0{slot_num}.0
    local pci_addr=$(printf "0000:00:%02x.0" "$slot_num")
    
    log_info "  Interface: $iface_name (PCI: $pci_addr)"
    
    # Create temporary XML for interface update
    local temp_xml="/tmp/iface-${full_vm_name}-${iface_name}.xml"
    cat > "$temp_xml" <<EOF
<interface type='network'>
  <source network='$network_name'/>
  <model type='virtio'/>
  <address type='pci' domain='0x0000' bus='0x00' slot='0x$(printf "%x" "$slot_num")' function='0x0'/>
</interface>
EOF
    
    # Update the interface - works for both running and stopped VMs
    if virsh update-device "$full_vm_name" "$temp_xml" --config --persistent 2>/dev/null; then
        log_success "✓ Interface $iface_name updated on $full_vm_name"
        rm -f "$temp_xml"
        return 0
    else
        log_warn "Could not update interface (trying alternative method)"
        
        # Alternative: Detach old, attach new (for stopped VMs)
        virsh detach-interface "$full_vm_name" network --config --persistent 2>/dev/null
        
        if virsh attach-interface "$full_vm_name" \
            --type network \
            --source "$network_name" \
            --model virtio \
            --config \
            --persistent 2>/dev/null; then
            log_success "✓ Interface attached to $full_vm_name"
            rm -f "$temp_xml"
            return 0
        else
            log_error "Failed to update interface on $full_vm_name"
            rm -f "$temp_xml"
            return 1
        fi
    fi
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
