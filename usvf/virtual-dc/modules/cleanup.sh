#!/bin/bash
################################################################################
# Cleanup and Destroy Module
#
# Safely destroys all virtual DC resources including:
# - Virtual machines (hypervisors and switches)
# - Virtual networks
# - Disk images
# - Cloud-init configurations
# - SSH keys (optional)
################################################################################

destroy_virtual_dc() {
    local config_file="$1"
    local force="${2:-false}"
    local keep_images="${3:-false}"
    
    log_warn "╔════════════════════════════════════════════════════════════╗"
    log_warn "║  WARNING: This will destroy all Virtual DC resources!     ║"
    log_warn "╚════════════════════════════════════════════════════════════╝"
    
    if [[ "$force" != "true" ]]; then
        echo ""
        read -p "Are you sure you want to destroy ALL resources? (type 'yes' to confirm): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Cleanup cancelled."
            return 0
        fi
    fi
    
    log_info "Starting Virtual DC cleanup..."
    
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file" 2>/dev/null || echo "virtual-dc-lab")
    
    # Stop and destroy VMs
    destroy_all_vms "$config_file"
    
    # Destroy virtual networks
    destroy_virtual_networks "$dc_name"
    
    # Remove disk images
    if [[ "$keep_images" != "true" ]]; then
        remove_disk_images "$dc_name"
    else
        log_info "Keeping disk images as requested"
    fi
    
    # Remove cloud-init files
    remove_cloud_init_configs "$dc_name"
    
    # Remove BGP configs
    remove_bgp_configs "$dc_name"
    
    # Remove SSH keys (ask user)
    remove_ssh_keys "$dc_name"
    
    # Remove verification reports
    remove_reports "$dc_name"
    
    log_success "✓ Virtual DC cleanup completed"
    log_info ""
    log_info "Summary:"
    log_info "  - All VMs destroyed"
    log_info "  - All networks removed"
    if [[ "$keep_images" != "true" ]]; then
        log_info "  - All disk images deleted"
    fi
    log_info "  - All configuration files cleaned"
}

destroy_all_vms() {
    local config_file="$1"
    
    log_info "Destroying all VMs..."
    
    # Get list of all VMs from virsh
    local all_vms=$(virsh list --all --name)
    
    if [[ -z "$all_vms" ]]; then
        log_info "No VMs found to destroy"
        return 0
    fi
    
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file" 2>/dev/null || echo "virtual-dc")
    
    # Destroy hypervisors (with DC prefix)
    local hv_count=$(yq eval '.hypervisors | length' "$config_file" 2>/dev/null || echo "0")
    if [[ "$hv_count" -gt 0 ]]; then
        for i in $(seq 0 $((hv_count - 1))); do
            local hv_name=$(yq eval ".hypervisors[$i].name" "$config_file" 2>/dev/null)
            if [[ -n "$hv_name" ]] && [[ "$hv_name" != "null" ]]; then
                local full_vm_name="${dc_name}-${hv_name}"
                destroy_single_vm "$full_vm_name"
            fi
        done
    fi
    
    # Destroy switches (with DC prefix)
    local switch_types=("leaf" "spine" "superspine")
    for switch_type in "${switch_types[@]}"; do
        local sw_count=$(yq eval ".switches.${switch_type} | length" "$config_file" 2>/dev/null || echo "0")
        if [[ "$sw_count" -gt 0 ]]; then
            for i in $(seq 0 $((sw_count - 1))); do
                local sw_name=$(yq eval ".switches.${switch_type}[$i].name" "$config_file" 2>/dev/null)
                if [[ -n "$sw_name" ]] && [[ "$sw_name" != "null" ]]; then
                    local full_vm_name="${dc_name}-${sw_name}"
                    destroy_single_vm "$full_vm_name"
                fi
            done
        fi
    done
    
    # Cleanup any remaining VMs that match DC prefix pattern
    for vm in $all_vms; do
        if [[ "$vm" =~ ^${dc_name}- ]]; then
            destroy_single_vm "$vm"
        fi
    done
    
    log_success "✓ All VMs destroyed"
}

destroy_single_vm() {
    local vm_name="$1"
    
    if [[ -z "$vm_name" ]] || [[ "$vm_name" == "null" ]]; then
        return 0
    fi
    
    # Check if VM exists
    if ! virsh list --all --name | grep -q "^${vm_name}$"; then
        return 0
    fi
    
    log_info "Destroying VM: $vm_name"
    
    # Force stop if running
    if virsh list --name | grep -q "^${vm_name}$"; then
        virsh destroy "$vm_name" 2>/dev/null || true
        sleep 1
    fi
    
    # Undefine VM with all storage
    virsh undefine "$vm_name" --remove-all-storage 2>/dev/null || \
    virsh undefine "$vm_name" --storage vda 2>/dev/null || \
    virsh undefine "$vm_name" 2>/dev/null || true
    
    log_success "  ✓ $vm_name destroyed"
}

destroy_virtual_networks() {
    local dc_name="$1"
    
    log_info "Destroying virtual networks..."
    
    # Common network patterns
    local network_patterns=(
        "${dc_name}-mgmt"
        "${dc_name}-data"
        "${dc_name}-fabric"
        "virtual-dc-.*"
    )
    
    local networks=$(virsh net-list --all --name)
    
    for network in $networks; do
        # Check if network matches our patterns
        local should_delete=false
        for pattern in "${network_patterns[@]}"; do
            if [[ "$network" =~ $pattern ]]; then
                should_delete=true
                break
            fi
        done
        
        if [[ "$should_delete" == "true" ]]; then
            log_info "Destroying network: $network"
            
            # Destroy if active
            if virsh net-list --name | grep -q "^${network}$"; then
                virsh net-destroy "$network" 2>/dev/null || true
            fi
            
            # Undefine
            virsh net-undefine "$network" 2>/dev/null || true
            log_success "  ✓ $network destroyed"
        fi
    done
    
    log_success "✓ Virtual networks destroyed"
}

remove_disk_images() {
    local dc_name="$1"
    
    log_info "Removing disk images..."
    
    local disk_dir=$(get_vdc_disks_dir "$dc_name")
    
    if [[ -d "$disk_dir" ]]; then
        local disk_count=$(find "$disk_dir" -name "*.qcow2" | wc -l)
        if [[ $disk_count -gt 0 ]]; then
            log_info "Found $disk_count disk images to remove"
            rm -rf "$disk_dir"/*.qcow2
            log_success "  ✓ Removed $disk_count disk images"
        else
            log_info "No disk images found"
        fi
    else
        log_info "Disk directory not found"
    fi
    
    log_success "✓ Disk images removed"
}

remove_cloud_init_configs() {
    local dc_name="$1"
    
    log_info "Removing cloud-init configurations..."
    
    local cloud_init_dir=$(get_vdc_cloud_init_dir "$dc_name")
    
    if [[ -d "$cloud_init_dir" ]]; then
        local iso_count=$(find "$cloud_init_dir" -name "*.iso" | wc -l)
        local dir_count=$(find "$cloud_init_dir" -maxdepth 1 -type d | wc -l)
        
        if [[ $iso_count -gt 0 ]] || [[ $dir_count -gt 1 ]]; then
            rm -rf "$cloud_init_dir"/*
            log_success "  ✓ Removed cloud-init configurations"
        else
            log_info "No cloud-init configurations found"
        fi
    else
        log_info "Cloud-init directory not found"
    fi
    
    log_success "✓ Cloud-init configurations removed"
}

remove_bgp_configs() {
    local dc_name="$1"
    
    log_info "Removing BGP configurations..."
    
    local bgp_config_dir=$(get_vdc_bgp_configs_dir "$dc_name")
    
    if [[ -d "$bgp_config_dir" ]]; then
        rm -rf "$bgp_config_dir"/*
        log_success "  ✓ Removed BGP configurations"
    else
        log_info "BGP config directory not found"
    fi
    
    log_success "✓ BGP configurations removed"
}

remove_ssh_keys() {
    local dc_name="$1"
    
    log_info "Checking SSH keys..."
    
    local ssh_key_path=$(get_vdc_ssh_private_key "$dc_name")
    local ssh_pubkey_path=$(get_vdc_ssh_public_key "$dc_name")
    
    if [[ -f "$ssh_key_path" ]] || [[ -f "$ssh_pubkey_path" ]]; then
        echo ""
        read -p "Remove SSH keys for $dc_name? (y/N): " remove_keys
        if [[ "$remove_keys" =~ ^[Yy]$ ]]; then
            rm -f "$ssh_key_path" "$ssh_pubkey_path"
            log_success "  ✓ SSH keys removed"
        else
            log_info "  ✓ SSH keys preserved"
        fi
    else
        log_info "No SSH keys found"
    fi
}

remove_reports() {
    local dc_name="$1"
    
    log_info "Removing verification reports..."
    
    local report_files=(
        "$PROJECT_ROOT/config/verification-report.txt"
        "$PROJECT_ROOT/config/deployment-summary.txt"
        "$PROJECT_ROOT/config/topology-map.txt"
    )
    
    for report in "${report_files[@]}"; do
        if [[ -f "$report" ]]; then
            rm -f "$report"
        fi
    done
    
    log_success "✓ Reports removed"
}

stop_all_vms() {
    local config_file="$1"
    
    log_info "Stopping all VMs..."
    
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file" 2>/dev/null || echo "virtual-dc")
    
    # Get hypervisors (with DC prefix)
    local hv_count=$(yq eval '.hypervisors | length' "$config_file" 2>/dev/null || echo "0")
    if [[ "$hv_count" -gt 0 ]]; then
        for i in $(seq 0 $((hv_count - 1))); do
            local hv_name=$(yq eval ".hypervisors[$i].name" "$config_file" 2>/dev/null)
            if [[ -n "$hv_name" ]] && [[ "$hv_name" != "null" ]]; then
                local full_vm_name="${dc_name}-${hv_name}"
                stop_single_vm "$full_vm_name"
            fi
        done
    fi
    
    # Get switches (with DC prefix)
    local switch_types=("leaf" "spine" "superspine")
    for switch_type in "${switch_types[@]}"; do
        local sw_count=$(yq eval ".switches.${switch_type} | length" "$config_file" 2>/dev/null || echo "0")
        if [[ "$sw_count" -gt 0 ]]; then
            for i in $(seq 0 $((sw_count - 1))); do
                local sw_name=$(yq eval ".switches.${switch_type}[$i].name" "$config_file" 2>/dev/null)
                if [[ -n "$sw_name" ]] && [[ "$sw_name" != "null" ]]; then
                    local full_vm_name="${dc_name}-${sw_name}"
                    stop_single_vm "$full_vm_name"
                fi
            done
        fi
    done
    
    log_success "✓ All VMs stopped"
}

stop_single_vm() {
    local vm_name="$1"
    
    if [[ -z "$vm_name" ]] || [[ "$vm_name" == "null" ]]; then
        return 0
    fi
    
    # Check if VM is running
    if virsh list --name | grep -q "^${vm_name}$"; then
        log_info "Stopping VM: $vm_name"
        virsh shutdown "$vm_name" 2>/dev/null || true
        log_success "  ✓ $vm_name stopped"
    fi
}

start_all_vms() {
    local config_file="$1"
    
    log_info "Starting all VMs..."
    
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file" 2>/dev/null || echo "virtual-dc")
    
    # Get hypervisors (with DC prefix)
    local hv_count=$(yq eval '.hypervisors | length' "$config_file" 2>/dev/null || echo "0")
    if [[ "$hv_count" -gt 0 ]]; then
        for i in $(seq 0 $((hv_count - 1))); do
            local hv_name=$(yq eval ".hypervisors[$i].name" "$config_file" 2>/dev/null)
            if [[ -n "$hv_name" ]] && [[ "$hv_name" != "null" ]]; then
                local full_vm_name="${dc_name}-${hv_name}"
                start_single_vm "$full_vm_name"
            fi
        done
    fi
    
    # Get switches (with DC prefix)
    local switch_types=("leaf" "spine" "superspine")
    for switch_type in "${switch_types[@]}"; do
        local sw_count=$(yq eval ".switches.${switch_type} | length" "$config_file" 2>/dev/null || echo "0")
        if [[ "$sw_count" -gt 0 ]]; then
            for i in $(seq 0 $((sw_count - 1))); do
                local sw_name=$(yq eval ".switches.${switch_type}[$i].name" "$config_file" 2>/dev/null)
                if [[ -n "$sw_name" ]] && [[ "$sw_name" != "null" ]]; then
                    local full_vm_name="${dc_name}-${sw_name}"
                    start_single_vm "$full_vm_name"
                fi
            done
        fi
    done
    
    log_success "✓ All VMs started"
}

start_single_vm() {
    local vm_name="$1"
    
    if [[ -z "$vm_name" ]] || [[ "$vm_name" == "null" ]]; then
        return 0
    fi
    
    # Check if VM exists and is not running
    if virsh list --all --name | grep -q "^${vm_name}$"; then
        if ! virsh list --name | grep -q "^${vm_name}$"; then
            log_info "Starting VM: $vm_name"
            virsh start "$vm_name" 2>/dev/null || true
            log_success "  ✓ $vm_name started"
        fi
    fi
}

list_resources() {
    local config_file="$1"
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file" 2>/dev/null || echo "virtual-dc-lab")
    
    log_info "Virtual DC Resources for: $dc_name"
    log_info "═══════════════════════════════════════════════════════"
    
    # List VMs (with DC prefix)
    echo ""
    log_info "Virtual Machines:"
    virsh list --all | grep -E "$dc_name-" || echo "  No VMs found"
    
    # List Networks
    echo ""
    log_info "Virtual Networks:"
    virsh net-list --all | grep -E "$dc_name|virtual-dc" || echo "  No networks found"
    
    # Disk usage
    echo ""
    log_info "Disk Images:"
    local disk_dir=$(get_vdc_disks_dir "$dc_name")
    if [[ -d "$disk_dir" ]]; then
        du -sh "$disk_dir"/*.qcow2 2>/dev/null || echo "  No disk images found"
    else
        echo "  No disk directory found"
    fi
    
    # Cloud-init ISOs
    echo ""
    log_info "Cloud-init ISOs:"
    local cloud_init_dir=$(get_vdc_cloud_init_dir "$dc_name")
    if [[ -d "$cloud_init_dir" ]]; then
        find "$cloud_init_dir" -name "*.iso" -exec du -sh {} \; 2>/dev/null || echo "  No ISOs found"
    else
        echo "  No cloud-init directory found"
    fi
    
    log_info "═══════════════════════════════════════════════════════"
}
