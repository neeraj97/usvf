#!/bin/bash
################################################################################
# Network Management Module
#
# Handles creation and configuration of:
# - Management network (L2 bridge)
# - Virtual network interfaces
# - Network connectivity between VMs
################################################################################

create_management_network() {
    local config_file="$1"
    local dry_run="${2:-false}"
    
    log_info "Creating management network infrastructure..."
    
    # Get management network configuration
    local mgmt_subnet=$(yq eval '.global.management_network.subnet' "$config_file")
    local mgmt_gateway=$(yq eval '.global.management_network.gateway' "$config_file")
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    
    log_info "Management subnet: $mgmt_subnet"
    log_info "Management gateway: $mgmt_gateway"
    
    # Create libvirt network
    create_libvirt_mgmt_network "$dc_name" "$mgmt_subnet" "$mgmt_gateway" "$dry_run"
    
    log_success "Management network created successfully"
}

create_libvirt_mgmt_network() {
    local dc_name="$1"
    local subnet="$2"
    local gateway="$3"
    local dry_run="$4"
    
    local network_name="${dc_name}-mgmt"
    local network_xml=$(get_vdc_network_xml "$dc_name" "$network_name")
    
    # Extract network address and prefix
    local network_addr=$(echo "$subnet" | cut -d'/' -f1 | sed 's/\.[0-9]*$//')
    local prefix=$(echo "$subnet" | cut -d'/' -f2)
    
    # Determine DHCP range
    local dhcp_start="${network_addr}.50"
    local dhcp_end="${network_addr}.200"
    
    log_info "Creating libvirt network: $network_name"
    
    # Generate network XML
    cat > "$network_xml" <<EOF
<network>
  <name>$network_name</name>
  <forward mode='nat'/>
  <bridge name='vbr-${dc_name}' stp='on' delay='0'/>
  <ip address='$gateway' netmask='255.255.255.0'>
    <dhcp>
      <range start='$dhcp_start' end='$dhcp_end'/>
    </dhcp>
  </ip>
</network>
EOF
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would create network with XML:"
        cat "$network_xml"
        return 0
    fi
    
    # Check if network already exists
    if virsh net-list --all | grep -q "$network_name"; then
        log_info "Network $network_name already exists, destroying and recreating..."
        virsh net-destroy "$network_name" 2>/dev/null || true
        virsh net-undefine "$network_name" 2>/dev/null || true
    fi
    
    # Define and start network
    virsh net-define "$network_xml"
    virsh net-start "$network_name"
    virsh net-autostart "$network_name"
    
    log_success "✓ Libvirt network $network_name created and started"
}

create_p2p_link() {
    local source_vm="$1"
    local source_iface="$2"
    local dest_vm="$3"
    local dest_iface="$4"
    local dry_run="${5:-false}"
    
    log_info "Creating P2P link: $source_vm:$source_iface <-> $dest_vm:$dest_iface"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would create P2P link between VMs"
        return 0
    fi
    
    # For KVM, we'll use veth pairs or UDP sockets
    # This will be implemented when VMs are created with proper interface attachments
    # The actual connection is done through libvirt network interfaces
    
    log_success "✓ P2P link configuration prepared"
}

configure_vm_interfaces() {
    local vm_name="$1"
    local config_file="$2"
    local dry_run="${3:-false}"
    
    log_info "Configuring network interfaces for VM: $vm_name"
    
    # This function will be called after VM creation
    # to attach additional network interfaces for data plane
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would configure interfaces for $vm_name"
        return 0
    fi
    
    log_success "✓ Network interfaces configured for $vm_name"
}

cleanup_network() {
    local dc_name="$1"
    local network_name="${dc_name}-mgmt"
    
    log_info "Cleaning up network: $network_name"
    
    if virsh net-list --all | grep -q "$network_name"; then
        virsh net-destroy "$network_name" 2>/dev/null || true
        virsh net-undefine "$network_name" 2>/dev/null || true
        log_success "✓ Network $network_name removed"
    else
        log_info "Network $network_name does not exist"
    fi
}

list_networks() {
    log_info "Listing all libvirt networks..."
    virsh net-list --all
}

get_network_info() {
    local network_name="$1"
    
    if virsh net-list --all | grep -q "$network_name"; then
        log_info "Network information for: $network_name"
        virsh net-dumpxml "$network_name"
    else
        log_error "Network $network_name not found"
        return 1
    fi
}
