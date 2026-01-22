#!/bin/bash
################################################################################
# VDC Module - Virtual Datacenter Operations
#
# Provides functions for managing VDC lifecycle:
# - Deployment
# - Destruction
# - Status reporting
# - Resource listing
# - Topology display
# - Orphan cleanup
################################################################################

# Ensure PROJECT_ROOT is set
: "${PROJECT_ROOT:?PROJECT_ROOT must be set}"

################################################################################
# VDC Deployment
################################################################################

deploy_vdc() {
    local vdc_name="$1"
    local config_file="$2"
    
    log_info "Deploying VDC: $vdc_name"
    
    # Ensure VDC directory structure exists
    ensure_vdc_directories "$vdc_name"
    
    # Call the main deployment script with VDC-specific parameters
    local deploy_script="$PROJECT_ROOT/scripts/deploy-virtual-dc.sh"
    
    if [[ ! -x "$deploy_script" ]]; then
        log_error "Deployment script not found or not executable: $deploy_script"
        return 1
    fi
    
    # Set environment variable for VDC mode
    export VDC_NAME="$vdc_name"
    export VDC_CONFIG="$config_file"
    
    # Run deployment
    "$deploy_script" --config "$config_file" 
    
    # Unset environment variables
    unset VDC_NAME VDC_CONFIG
    
    log_success "VDC '$vdc_name' deployed"
}

################################################################################
# VDC Destruction
################################################################################

destroy_vdc() {
    local vdc_name="$1"
    
    log_info "Destroying all resources for VDC: $vdc_name"
    
    # Destroy all VMs belonging to this VDC
    destroy_vdc_vms "$vdc_name"
    
    # Destroy all networks belonging to this VDC
    destroy_vdc_networks "$vdc_name"
    
    # Clean up disk images
    destroy_vdc_disks "$vdc_name"
    
    # Clean up cloud-init files
    destroy_vdc_cloud_init "$vdc_name"
    
    log_success "VDC '$vdc_name' resources destroyed"
}

destroy_vdc_vms() {
    local vdc_name="$1"
    
    log_info "Destroying VMs for VDC: $vdc_name"
    
    # Get list of VMs with VDC prefix
    local vms=$(virsh list --all --name 2>/dev/null | grep "^${vdc_name}-" || true)
    
    if [[ -z "$vms" ]]; then
        log_info "No VMs found for VDC: $vdc_name"
        return 0
    fi
    
    while IFS= read -r vm; do
        if [[ -n "$vm" ]]; then
            log_info "  Destroying VM: $vm"
            
            # Stop if running
            if virsh list --name 2>/dev/null | grep -q "^${vm}$"; then
                virsh destroy "$vm" 2>/dev/null || true
            fi
            
            # Undefine
            virsh undefine "$vm" --remove-all-storage 2>/dev/null || true
        fi
    done <<< "$vms"
    
    log_success "Destroyed VMs for VDC: $vdc_name"
}

destroy_vdc_networks() {
    local vdc_name="$1"
    
    log_info "Destroying networks for VDC: $vdc_name"
    
    # Get list of networks with VDC prefix
    local networks=$(virsh net-list --all --name 2>/dev/null | grep "^${vdc_name}-" || true)
    
    if [[ -z "$networks" ]]; then
        log_info "No networks found for VDC: $vdc_name"
        return 0
    fi
    
    while IFS= read -r network; do
        if [[ -n "$network" ]]; then
            log_info "  Destroying network: $network"
            
            # Destroy if active
            if virsh net-list --name 2>/dev/null | grep -q "^${network}$"; then
                virsh net-destroy "$network" 2>/dev/null || true
            fi
            
            # Undefine
            virsh net-undefine "$network" 2>/dev/null || true
        fi
    done <<< "$networks"
    
    log_success "Destroyed networks for VDC: $vdc_name"
}

destroy_vdc_disks() {
    local vdc_name="$1"
    
    log_info "Cleaning up disk images for VDC: $vdc_name"
    
    local disk_dir=$(get_vdc_disks_dir "$vdc_name")
    
    if [[ -d "$disk_dir" ]]; then
        # Remove all disks in VDC disk directory
        find "$disk_dir" -name "*.qcow2" -delete 2>/dev/null || true
        log_success "Cleaned up disk images"
    fi
}

destroy_vdc_cloud_init() {
    local vdc_name="$1"
    
    log_info "Cleaning up cloud-init files for VDC: $vdc_name"
    
    local cloud_init_dir=$(get_vdc_cloud_init_dir "$vdc_name")
    
    if [[ -d "$cloud_init_dir" ]]; then
        # Remove all cloud-init files in VDC cloud-init directory
        rm -rf "$cloud_init_dir"/*
        log_success "Cleaned up cloud-init files"
    fi
}

################################################################################
# VDC Status
################################################################################

show_vdc_status() {
    local vdc_name="$1"
    
    log_info "═══════════════════════════════════════════════════════════"
    log_info "         STATUS: Virtual Datacenter '$vdc_name'"
    log_info "═══════════════════════════════════════════════════════════"
    echo ""
    
    # Get VDC info from registry
    local vdc_info=$(get_vdc_info "$vdc_name")
    local namespace=$(echo "$vdc_info" | jq -r '.namespace')
    local created_at=$(echo "$vdc_info" | jq -r '.created_at')
    local mgmt_subnet=$(echo "$vdc_info" | jq -r '.management_subnet')
    
    echo "VDC Name:          $vdc_name"
    echo "Namespace:         $namespace"
    echo "Created:           $created_at"
    echo "Management Subnet: $mgmt_subnet"
    echo ""
    
    # Check namespace status
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "NETWORK NAMESPACE STATUS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if ip netns list 2>/dev/null | grep -q "^${namespace}"; then
        echo "Status: ✓ Active"
        echo ""
        echo "Interfaces in namespace:"
        ip netns exec "$namespace" ip link show 2>/dev/null | grep -E "^[0-9]+" || echo "  None"
    else
        echo "Status: ✗ Not found"
    fi
    echo ""
    
    # VM Status
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "VIRTUAL MACHINES"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local all_vms=$(virsh list --all --name 2>/dev/null | grep "^${vdc_name}-" || true)
    
    if [[ -z "$all_vms" ]]; then
        echo "No VMs found"
    else
        printf "%-30s %-15s %-10s %-10s\n" "VM NAME" "STATE" "CPU" "MEMORY"
        printf "%-30s %-15s %-10s %-10s\n" "-------" "-----" "---" "------"
        
        while IFS= read -r vm; do
            if [[ -n "$vm" ]]; then
                local state=$(virsh domstate "$vm" 2>/dev/null || echo "unknown")
                local vcpu=$(virsh dominfo "$vm" 2>/dev/null | grep "CPU(s):" | awk '{print $2}' || echo "-")
                local mem=$(virsh dominfo "$vm" 2>/dev/null | grep "Max memory:" | awk '{print $3 " " $4}' || echo "-")
                printf "%-30s %-15s %-10s %-10s\n" "$vm" "$state" "$vcpu" "$mem"
            fi
        done <<< "$all_vms"
    fi
    echo ""
    
    # Network Status
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "VIRTUAL NETWORKS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local all_networks=$(virsh net-list --all --name 2>/dev/null | grep "^${vdc_name}-" || true)
    
    if [[ -z "$all_networks" ]]; then
        echo "No networks found"
    else
        printf "%-30s %-15s %-20s\n" "NETWORK NAME" "STATE" "BRIDGE"
        printf "%-30s %-15s %-20s\n" "------------" "-----" "------"
        
        while IFS= read -r network; do
            if [[ -n "$network" ]]; then
                local state=$(virsh net-info "$network" 2>/dev/null | grep "Active:" | awk '{print $2}' || echo "unknown")
                local bridge=$(virsh net-info "$network" 2>/dev/null | grep "Bridge:" | awk '{print $2}' || echo "-")
                printf "%-30s %-15s %-20s\n" "$network" "$state" "$bridge"
            fi
        done <<< "$all_networks"
    fi
    echo ""
    
    log_info "═══════════════════════════════════════════════════════════"
}

################################################################################
# VDC Resources
################################################################################

show_vdc_resources() {
    local vdc_name="$1"
    
    log_info "═══════════════════════════════════════════════════════════"
    log_info "       RESOURCES: Virtual Datacenter '$vdc_name'"
    log_info "═══════════════════════════════════════════════════════════"
    echo ""
    
    # Hypervisors
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "HYPERVISORS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local hypervisors=$(virsh list --all --name 2>/dev/null | grep "^${vdc_name}-hv" || grep "^${vdc_name}-hypervisor" || true)
    
    if [[ -z "$hypervisors" ]]; then
        echo "No hypervisors found"
    else
        printf "%-30s %-15s %-10s %-10s %-20s\n" "NAME" "STATE" "VCPU" "MEMORY" "MANAGEMENT IP"
        printf "%-30s %-15s %-10s %-10s %-20s\n" "----" "-----" "----" "------" "-------------"
        
        while IFS= read -r hv; do
            if [[ -n "$hv" ]]; then
                local state=$(virsh domstate "$hv" 2>/dev/null || echo "unknown")
                local vcpu=$(virsh dominfo "$hv" 2>/dev/null | grep "CPU(s):" | awk '{print $2}' || echo "-")
                local mem=$(virsh dominfo "$hv" 2>/dev/null | grep "Used memory:" | awk '{print $3 " " $4}' || echo "-")
                
                # Try to get IP from DHCP leases or ARP
                local ip=$(virsh domifaddr "$hv" 2>/dev/null | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -1 || echo "-")
                
                printf "%-30s %-15s %-10s %-10s %-20s\n" "$hv" "$state" "$vcpu" "$mem" "$ip"
            fi
        done <<< "$hypervisors"
    fi
    echo ""
    
    # Switches
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "SONIC SWITCHES"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local switches=$(virsh list --all --name 2>/dev/null | grep "^${vdc_name}-" | grep -E "(leaf|spine|superspine)" || true)
    
    if [[ -z "$switches" ]]; then
        echo "No switches found"
    else
        printf "%-30s %-15s %-10s %-10s %-20s\n" "NAME" "STATE" "VCPU" "MEMORY" "MANAGEMENT IP"
        printf "%-30s %-15s %-10s %-10s %-20s\n" "----" "-----" "----" "------" "-------------"
        
        while IFS= read -r sw; do
            if [[ -n "$sw" ]]; then
                local state=$(virsh domstate "$sw" 2>/dev/null || echo "unknown")
                local vcpu=$(virsh dominfo "$sw" 2>/dev/null | grep "CPU(s):" | awk '{print $2}' || echo "-")
                local mem=$(virsh dominfo "$sw" 2>/dev/null | grep "Used memory:" | awk '{print $3 " " $4}' || echo "-")
                local ip=$(virsh domifaddr "$sw" 2>/dev/null | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -1 || echo "-")
                
                printf "%-30s %-15s %-10s %-10s %-20s\n" "$sw" "$state" "$vcpu" "$mem" "$ip"
            fi
        done <<< "$switches"
    fi
    echo ""
    
    # Disk Usage
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "DISK USAGE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local disk_dir=$(get_vdc_disks_dir "$vdc_name")
    if [[ -d "$disk_dir" ]]; then
        local disk_count=$(count_vdc_disks "$vdc_name")
        local total_size=$(get_vdc_total_disk_usage "$vdc_name")
        
        echo "Total Disks:  $disk_count"
        echo "Total Size:   $total_size"
    else
        echo "No disk directory found"
    fi
    echo ""
    
    log_info "═══════════════════════════════════════════════════════════"
}

################################################################################
# VDC Topology
################################################################################

show_vdc_topology() {
    local vdc_name="$1"
    
    log_info "═══════════════════════════════════════════════════════════"
    log_info "       TOPOLOGY: Virtual Datacenter '$vdc_name'"
    log_info "═══════════════════════════════════════════════════════════"
    echo ""
    
    # Load topology from config file
    local config_file="$PROJECT_ROOT/config/vdc-${vdc_name}/topology.yaml"
    
    if [[ ! -f "$config_file" ]]; then
        log_warn "Topology configuration not found: $config_file"
        return 1
    fi
    
    # Display visual topology from config
    echo "TOPOLOGY DIAGRAM:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    yq eval '.topology_visual' "$config_file" 2>/dev/null || echo "No visual topology in config"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "CABLING LAYOUT:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Display cabling information
    local cabling_count=$(yq eval '.cabling | length' "$config_file" 2>/dev/null || echo "0")
    
    if [[ $cabling_count -gt 0 ]]; then
        printf "%-25s %-20s <---> %-25s %-20s\n" "SOURCE DEVICE" "INTERFACE" "DEST DEVICE" "INTERFACE"
        printf "%-25s %-20s       %-25s %-20s\n" "-------------" "---------" "-----------" "---------"
        
        for i in $(seq 0 $((cabling_count - 1))); do
            local src_dev=$(yq eval ".cabling[$i].source.device" "$config_file")
            local src_int=$(yq eval ".cabling[$i].source.interface" "$config_file")
            local dst_dev=$(yq eval ".cabling[$i].destination.device" "$config_file")
            local dst_int=$(yq eval ".cabling[$i].destination.interface" "$config_file")
            
            printf "%-25s %-20s <---> %-25s %-20s\n" "$src_dev" "$src_int" "$dst_dev" "$dst_int"
        done
    else
        echo "No cabling defined"
    fi
    
    echo ""
    log_info "═══════════════════════════════════════════════════════════"
}

################################################################################
# Orphan Cleanup
################################################################################

cleanup_orphaned_resources() {
    local vdc_name="$1"
    local force="${2:-false}"
    
    log_info "═══════════════════════════════════════════════════════════"
    log_info "   ORPHAN CLEANUP: Virtual Datacenter '$vdc_name'"
    log_info "═══════════════════════════════════════════════════════════"
    echo ""
    
    # Find orphaned VMs (VMs with VDC prefix but not in config)
    log_info "Scanning for orphaned VMs..."
    local orphaned_vms=$(find_orphaned_vms "$vdc_name")
    
    # Find orphaned networks
    log_info "Scanning for orphaned networks..."
    local orphaned_networks=$(find_orphaned_networks "$vdc_name")
    
    # Find orphaned disks
    log_info "Scanning for orphaned disks..."
    local orphaned_disks=$(find_orphaned_disks "$vdc_name")
    
    # Report findings
    echo ""
    echo "ORPHANED RESOURCES FOUND:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local orphan_count=0
    
    if [[ -n "$orphaned_vms" ]]; then
        echo ""
        echo "Orphaned VMs:"
        while IFS= read -r vm; do
            if [[ -n "$vm" ]]; then
                echo "  - $vm"
                orphan_count=$((orphan_count + 1))
            fi
        done <<< "$orphaned_vms"
    fi
    
    if [[ -n "$orphaned_networks" ]]; then
        echo ""
        echo "Orphaned Networks:"
        while IFS= read -r net; do
            if [[ -n "$net" ]]; then
                echo "  - $net"
                orphan_count=$((orphan_count + 1))
            fi
        done <<< "$orphaned_networks"
    fi
    
    if [[ -n "$orphaned_disks" ]]; then
        echo ""
        echo "Orphaned Disks:"
        while IFS= read -r disk; do
            if [[ -n "$disk" ]]; then
                echo "  - $disk"
                orphan_count=$((orphan_count + 1))
            fi
        done <<< "$orphaned_disks"
    fi
    
    echo ""
    
    if [[ $orphan_count -eq 0 ]]; then
        log_success "No orphaned resources found!"
        return 0
    fi
    
    echo "Total orphaned resources: $orphan_count"
    echo ""
    
    # Confirm cleanup
    if [[ "$force" != "true" ]]; then
        read -p "Do you want to clean up these orphaned resources? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Cleanup cancelled"
            return 0
        fi
    fi
    
    # Perform cleanup
    echo ""
    log_info "Cleaning up orphaned resources..."
    
    if [[ -n "$orphaned_vms" ]]; then
        while IFS= read -r vm; do
            if [[ -n "$vm" ]]; then
                log_info "  Removing VM: $vm"
                virsh destroy "$vm" 2>/dev/null || true
                virsh undefine "$vm" --remove-all-storage 2>/dev/null || true
            fi
        done <<< "$orphaned_vms"
    fi
    
    if [[ -n "$orphaned_networks" ]]; then
        while IFS= read -r net; do
            if [[ -n "$net" ]]; then
                log_info "  Removing network: $net"
                virsh net-destroy "$net" 2>/dev/null || true
                virsh net-undefine "$net" 2>/dev/null || true
            fi
        done <<< "$orphaned_networks"
    fi
    
    if [[ -n "$orphaned_disks" ]]; then
        while IFS= read -r disk; do
            if [[ -n "$disk" ]]; then
                log_info "  Removing disk: $disk"
                rm -f "$disk"
            fi
        done <<< "$orphaned_disks"
    fi
    
    echo ""
    log_success "Cleanup completed! Removed $orphan_count orphaned resources."
    log_info "═══════════════════════════════════════════════════════════"
}

find_orphaned_vms() {
    local vdc_name="$1"
    local config_file="$PROJECT_ROOT/config/vdc-${vdc_name}/topology.yaml"
    
    # Get all VMs with VDC prefix
    local all_vms=$(virsh list --all --name 2>/dev/null | grep "^${vdc_name}-" || true)
    
    if [[ -z "$all_vms" ]] || [[ ! -f "$config_file" ]]; then
        return 0
    fi
    
    # Get expected VMs from config
    local expected_vms=$(yq eval '.hypervisors[].name' "$config_file" 2>/dev/null | sed "s/^/${vdc_name}-/")
    expected_vms+=$'\n'$(yq eval '.switches.leaf[].name' "$config_file" 2>/dev/null | sed "s/^/${vdc_name}-/")
    expected_vms+=$'\n'$(yq eval '.switches.spine[].name' "$config_file" 2>/dev/null | sed "s/^/${vdc_name}-/")
    expected_vms+=$'\n'$(yq eval '.switches.superspine[].name' "$config_file" 2>/dev/null | sed "s/^/${vdc_name}-/")
    
    # Find orphans (VMs that exist but are not in config)
    while IFS= read -r vm; do
        if [[ -n "$vm" ]] && ! echo "$expected_vms" | grep -q "^${vm}$"; then
            echo "$vm"
        fi
    done <<< "$all_vms"
}

find_orphaned_networks() {
    local vdc_name="$1"
    
    # Get all networks with VDC prefix
    local all_networks=$(virsh net-list --all --name 2>/dev/null | grep "^${vdc_name}-" || true)
    
    if [[ -z "$all_networks" ]]; then
        return 0
    fi
    
    # Expected networks: management network
    local expected_network="${vdc_name}-mgmt"
    
    # Find orphans
    while IFS= read -r net; do
        if [[ -n "$net" ]] && [[ "$net" != "$expected_network" ]]; then
            echo "$net"
        fi
    done <<< "$all_networks"
}

find_orphaned_disks() {
    local vdc_name="$1"
    local disk_dir=$(get_vdc_disks_dir "$vdc_name")
    
    if [[ ! -d "$disk_dir" ]]; then
        return 0
    fi
    
    # Get all disks in VDC disk directory
    local all_disks=$(list_vdc_disks "$vdc_name")
    
    if [[ -z "$all_disks" ]]; then
        return 0
    fi
    
    # Get list of active VMs
    local active_vms=$(virsh list --all --name 2>/dev/null | grep "^${vdc_name}-" || true)
    
    # Find disks not associated with any VM
    while IFS= read -r disk; do
        if [[ -n "$disk" ]]; then
            local disk_name=$(basename "$disk" .qcow2)
            if ! echo "$active_vms" | grep -q "$disk_name"; then
                echo "$disk"
            fi
        fi
    done <<< "$all_disks"
}
