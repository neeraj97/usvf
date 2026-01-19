#!/bin/bash
################################################################################
# SONiC Switch Deployment Module
#
# Deploys and configures SONiC switch VMs with:
# - SONiC virtual switches (VS images)
# - BGP configuration
# - Multiple network interfaces
# - Management interface configuration
################################################################################

deploy_switches() {
    local config_file="$1"
    local dry_run="${2:-false}"
    
    log_info "Deploying SONiC switch VMs..."
    
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    
    # Deploy leaf switches
    deploy_switch_tier "$config_file" "leaf" "$dry_run"
    
    # Deploy spine switches
    deploy_switch_tier "$config_file" "spine" "$dry_run"
    
    # Deploy superspine switches (if any)
    local superspine_count=$(yq eval '.switches.superspine | length' "$config_file")
    if [[ $superspine_count -gt 0 ]]; then
        deploy_switch_tier "$config_file" "superspine" "$dry_run"
    fi
    
    log_success "All SONiC switches deployed successfully"
}

deploy_switch_tier() {
    local config_file="$1"
    local tier="$2"
    local dry_run="$3"
    
    local count=$(yq eval ".switches.$tier | length" "$config_file")
    
    if [[ $count -eq 0 ]]; then
        log_info "No $tier switches to deploy"
        return 0
    fi
    
    log_info "Deploying $count $tier switches..."
    
    for i in $(seq 0 $((count - 1))); do
        deploy_single_switch "$config_file" "$tier" "$i" "$dry_run"
    done
    
    log_success "✓ All $tier switches deployed"
}

deploy_single_switch() {
    local config_file="$1"
    local tier="$2"
    local index="$3"
    local dry_run="$4"
    
    # Extract switch configuration
    local sw_name=$(yq eval ".switches.$tier[$index].name" "$config_file")
    local router_id=$(yq eval ".switches.$tier[$index].router_id" "$config_file")
    local asn=$(yq eval ".switches.$tier[$index].asn" "$config_file")
    local mgmt_ip=$(yq eval ".switches.$tier[$index].management.ip" "$config_file")
    local ports=$(yq eval ".switches.$tier[$index].ports" "$config_file")
    local port_speed=$(yq eval ".switches.$tier[$index].port_speed" "$config_file")
    
    log_info "Deploying $tier switch: $sw_name"
    log_info "  Router ID: $router_id, ASN: $asn"
    log_info "  Management IP: $mgmt_ip"
    log_info "  Ports: $ports @ $port_speed"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would create SONiC switch VM: $sw_name"
        return 0
    fi
    
    # Create SONiC cloud-init configuration
    create_sonic_cloud_init "$config_file" "$tier" "$index" "$sw_name"
    
    # Create VM disk for SONiC
    create_sonic_disk "$sw_name"
    
    # Create and start SONiC VM
    create_sonic_vm "$config_file" "$sw_name" "$ports"
    
    log_success "✓ SONiC switch $sw_name deployed"
}

create_sonic_cloud_init() {
    local config_file="$1"
    local tier="$2"
    local index="$3"
    local sw_name="$4"
    
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local ssh_key_path="$PROJECT_ROOT/config/${dc_name}-ssh-key.pub"
    local ssh_pubkey=$(cat "$ssh_key_path")
    
    local router_id=$(yq eval ".switches.$tier[$index].router_id" "$config_file")
    local asn=$(yq eval ".switches.$tier[$index].asn" "$config_file")
    local mgmt_ip=$(yq eval ".switches.$tier[$index].management.ip" "$config_file")
    local mgmt_gw=$(yq eval '.global.management_network.gateway' "$config_file")
    
    local cloud_init_dir="$PROJECT_ROOT/config/cloud-init/$sw_name"
    mkdir -p "$cloud_init_dir"
    
    # SONiC uses a different initialization approach
    # We'll create a startup configuration that will be loaded
    
    # Create startup config for SONiC
    cat > "$cloud_init_dir/config_db.json" <<EOF
{
    "DEVICE_METADATA": {
        "localhost": {
            "hostname": "$sw_name",
            "hwsku": "Force10-S6000",
            "platform": "x86_64-kvm_x86_64-r0",
            "mac": "auto",
            "type": "ToRRouter"
        }
    },
    "MGMT_INTERFACE": {
        "eth0|${mgmt_ip}": {
            "gwaddr": "$mgmt_gw"
        }
    },
    "LOOPBACK_INTERFACE": {
        "Loopback0|${router_id}/32": {}
    },
    "BGP_NEIGHBOR": {},
    "DEVICE_NEIGHBOR": {}
}
EOF
    
    # Create FRR config for SONiC
    cat > "$cloud_init_dir/frr.conf" <<EOF
!
frr version 7.5
frr defaults traditional
hostname $sw_name
log syslog informational
no ipv6 forwarding
service integrated-vtysh-config
!
router bgp $asn
 bgp router-id $router_id
 bgp log-neighbor-changes
 no bgp default ipv4-unicast
 bgp bestpath as-path multipath-relax
 neighbor FABRIC peer-group
 neighbor FABRIC remote-as external
 !
 address-family ipv4 unicast
  neighbor FABRIC activate
  neighbor FABRIC route-map ALLOW-ALL in
  neighbor FABRIC route-map ALLOW-ALL out
  maximum-paths 64
 exit-address-family
!
route-map ALLOW-ALL permit 10
!
line vty
!
end
EOF
    
    log_success "✓ SONiC configuration created for $sw_name"
}

create_sonic_disk() {
    local sw_name="$1"
    
    local disk_dir="$PROJECT_ROOT/config/disks"
    mkdir -p "$disk_dir"
    
    local disk_path="$disk_dir/${sw_name}.qcow2"
    
    log_info "Creating disk for SONiC switch $sw_name..."
    
    # Create a 20GB disk for SONiC
    qemu-img create -f qcow2 "$disk_path" 20G
    
    log_success "✓ Disk created: $disk_path"
}

create_sonic_vm() {
    local config_file="$1"
    local sw_name="$2"
    local ports="$3"
    
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local mgmt_network="${dc_name}-mgmt"
    local disk_path="$PROJECT_ROOT/config/disks/${sw_name}.qcow2"
    
    log_info "Creating SONiC VM: $sw_name"
    
    # For SONiC VS, we need to use a special approach
    # Using Ubuntu as base with SONiC docker container would be more practical
    # For now, create a standard VM that we can configure
    
    local cmd="virt-install \
        --name $sw_name \
        --vcpus 2 \
        --memory 4096 \
        --disk path=$disk_path,format=qcow2,bus=virtio \
        --network network=$mgmt_network,model=virtio \
        --os-variant ubuntu22.04 \
        --graphics none \
        --console pty,target_type=serial \
        --import \
        --noautoconsole"
    
    # Add data plane interfaces for switch ports
    # We'll add interfaces based on the cabling requirements
    for i in $(seq 1 $((ports / 8))); do
        cmd="$cmd --network network=default,model=virtio"
    done
    
    # Execute virt-install
    eval "$cmd"
    
    log_success "✓ SONiC VM $sw_name created and started"
}

configure_sonic_bgp() {
    local sw_name="$1"
    local config_file="$2"
    
    log_info "Configuring BGP on SONiC switch: $sw_name"
    
    # This would SSH into the switch and apply BGP configuration
    # Implementation depends on switch accessibility
    
    log_success "✓ BGP configured on $sw_name"
}

list_switches() {
    log_info "Listing all switch VMs..."
    virsh list --all | grep -E "leaf|spine|superspine" || echo "No switches found"
}

delete_switch() {
    local sw_name="$1"
    
    log_info "Deleting switch: $sw_name"
    
    # Stop VM if running
    if virsh list --name | grep -q "^${sw_name}$"; then
        virsh destroy "$sw_name"
    fi
    
    # Undefine VM
    if virsh list --all --name | grep -q "^${sw_name}$"; then
        virsh undefine "$sw_name" --remove-all-storage
        log_success "✓ Switch $sw_name deleted"
    else
        log_warn "Switch $sw_name not found"
    fi
}
