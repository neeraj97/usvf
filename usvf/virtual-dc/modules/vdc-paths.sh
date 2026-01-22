#!/bin/bash
################################################################################
# VDC Paths Module - Centralized Path Management
#
# Provides consistent path management for VDC resources.
# All VDC resources are organized under config/vdc-{dcname}/ for easy cleanup.
#
# Directory structure:
#   config/vdc-{dcname}/
#     ├── topology.yaml          # VDC topology configuration
#     ├── disks/                 # VM disk images
#     ├── cloud-init/            # Cloud-init ISOs and configs
#     ├── bgp-configs/           # BGP configuration files
#     ├── network-xmls/          # Libvirt network XML files
#     └── ssh-keys/              # SSH keypairs
################################################################################

# Ensure PROJECT_ROOT is set
: "${PROJECT_ROOT:?PROJECT_ROOT must be set}"

################################################################################
# VDC Base Directory
################################################################################

get_vdc_base_dir() {
    local vdc_name="$1"
    echo "$PROJECT_ROOT/config/vdc-${vdc_name}"
}

get_vdc_topology_file() {
    local vdc_name="$1"
    echo "$(get_vdc_base_dir "$vdc_name")/topology.yaml"
}

################################################################################
# Disks Directory
################################################################################

get_vdc_disks_dir() {
    local vdc_name="$1"
    echo "$(get_vdc_base_dir "$vdc_name")/disks"
}

get_vdc_disk_path() {
    local vdc_name="$1"
    local vm_name="$2"
    echo "$(get_vdc_disks_dir "$vdc_name")/${vm_name}.qcow2"
}

################################################################################
# Cloud-Init Directory
################################################################################

get_vdc_cloud_init_dir() {
    local vdc_name="$1"
    echo "$(get_vdc_base_dir "$vdc_name")/cloud-init"
}

get_vdc_cloud_init_vm_dir() {
    local vdc_name="$1"
    local vm_name="$2"
    echo "$(get_vdc_cloud_init_dir "$vdc_name")/$vm_name"
}

get_vdc_cloud_init_iso() {
    local vdc_name="$1"
    local vm_name="$2"
    echo "$(get_vdc_cloud_init_dir "$vdc_name")/${vm_name}-cidata.iso"
}

################################################################################
# BGP Configs Directory
################################################################################

get_vdc_bgp_configs_dir() {
    local vdc_name="$1"
    echo "$(get_vdc_base_dir "$vdc_name")/bgp-configs"
}

get_vdc_bgp_config_file() {
    local vdc_name="$1"
    local device_name="$2"
    echo "$(get_vdc_bgp_configs_dir "$vdc_name")/${device_name}-bgp.conf"
}

################################################################################
# Network XMLs Directory
################################################################################

get_vdc_network_xmls_dir() {
    local vdc_name="$1"
    echo "$(get_vdc_base_dir "$vdc_name")/network-xmls"
}

get_vdc_network_xml() {
    local vdc_name="$1"
    local network_name="$2"
    echo "$(get_vdc_network_xmls_dir "$vdc_name")/${network_name}.xml"
}

################################################################################
# SSH Keys Directory
################################################################################

get_vdc_ssh_keys_dir() {
    local vdc_name="$1"
    echo "$(get_vdc_base_dir "$vdc_name")/ssh-keys"
}

get_vdc_ssh_private_key() {
    local vdc_name="$1"
    echo "$(get_vdc_ssh_keys_dir "$vdc_name")/id_rsa"
}

get_vdc_ssh_public_key() {
    local vdc_name="$1"
    echo "$(get_vdc_ssh_keys_dir "$vdc_name")/id_rsa.pub"
}

################################################################################
# Directory Creation
################################################################################

ensure_vdc_directories() {
    local vdc_name="$1"
    
    local base_dir=$(get_vdc_base_dir "$vdc_name")
    
    mkdir -p "$base_dir"
    mkdir -p "$(get_vdc_disks_dir "$vdc_name")"
    mkdir -p "$(get_vdc_cloud_init_dir "$vdc_name")"
    mkdir -p "$(get_vdc_bgp_configs_dir "$vdc_name")"
    mkdir -p "$(get_vdc_network_xmls_dir "$vdc_name")"
    mkdir -p "$(get_vdc_ssh_keys_dir "$vdc_name")"
    
    log_info "VDC directory structure created at: $base_dir"
}

################################################################################
# Cleanup
################################################################################

cleanup_vdc_directory() {
    local vdc_name="$1"
    local base_dir=$(get_vdc_base_dir "$vdc_name")
    
    if [[ -d "$base_dir" ]]; then
        log_info "Removing VDC directory: $base_dir"
        rm -rf "$base_dir"
        log_success "✓ VDC directory removed"
    else
        log_info "VDC directory does not exist: $base_dir"
    fi
}

list_vdc_resources() {
    local vdc_name="$1"
    local base_dir=$(get_vdc_base_dir "$vdc_name")
    
    if [[ ! -d "$base_dir" ]]; then
        log_error "VDC directory not found: $base_dir"
        return 1
    fi
    
    echo "VDC Resources for: $vdc_name"
    echo "Base directory: $base_dir"
    echo ""
    
    echo "Disks:"
    find "$(get_vdc_disks_dir "$vdc_name")" -name "*.qcow2" 2>/dev/null | while read -r disk; do
        local size=$(du -h "$disk" | cut -f1)
        echo "  $disk ($size)"
    done
    echo ""
    
    echo "Cloud-init ISOs:"
    find "$(get_vdc_cloud_init_dir "$vdc_name")" -name "*.iso" 2>/dev/null | while read -r iso; do
        local size=$(du -h "$iso" | cut -f1)
        echo "  $iso ($size)"
    done
    echo ""
    
    echo "BGP Configs:"
    find "$(get_vdc_bgp_configs_dir "$vdc_name")" -name "*.conf" 2>/dev/null | while read -r conf; do
        echo "  $conf"
    done
    echo ""
    
    echo "Network XMLs:"
    find "$(get_vdc_network_xmls_dir "$vdc_name")" -name "*.xml" 2>/dev/null | while read -r xml; do
        echo "  $xml"
    done
    echo ""
    
    echo "SSH Keys:"
    find "$(get_vdc_ssh_keys_dir "$vdc_name")" -type f 2>/dev/null | while read -r key; do
        echo "  $key"
    done
}

get_vdc_total_disk_usage() {
    local vdc_name="$1"
    local base_dir=$(get_vdc_base_dir "$vdc_name")
    
    if [[ -d "$base_dir" ]]; then
        du -sh "$base_dir" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

################################################################################
# Validation Functions
################################################################################

vdc_directory_exists() {
    local vdc_name="$1"
    local base_dir=$(get_vdc_base_dir "$vdc_name")
    [[ -d "$base_dir" ]]
}

vdc_topology_exists() {
    local vdc_name="$1"
    local topology_file=$(get_vdc_topology_file "$vdc_name")
    [[ -f "$topology_file" ]]
}

vdc_disk_exists() {
    local vdc_name="$1"
    local vm_name="$2"
    local disk_path=$(get_vdc_disk_path "$vdc_name" "$vm_name")
    [[ -f "$disk_path" ]]
}

vdc_cloud_init_iso_exists() {
    local vdc_name="$1"
    local vm_name="$2"
    local iso_path=$(get_vdc_cloud_init_iso "$vdc_name" "$vm_name")
    [[ -f "$iso_path" ]]
}

vdc_bgp_config_exists() {
    local vdc_name="$1"
    local device_name="$2"
    local bgp_config=$(get_vdc_bgp_config_file "$vdc_name" "$device_name")
    [[ -f "$bgp_config" ]]
}

vdc_network_xml_exists() {
    local vdc_name="$1"
    local network_name="$2"
    local network_xml=$(get_vdc_network_xml "$vdc_name" "$network_name")
    [[ -f "$network_xml" ]]
}

vdc_ssh_keys_exist() {
    local vdc_name="$1"
    local private_key=$(get_vdc_ssh_private_key "$vdc_name")
    local public_key=$(get_vdc_ssh_public_key "$vdc_name")
    [[ -f "$private_key" ]] && [[ -f "$public_key" ]]
}

################################################################################
# Resource Listing Functions
################################################################################

list_vdc_disks() {
    local vdc_name="$1"
    local disks_dir=$(get_vdc_disks_dir "$vdc_name")
    
    if [[ ! -d "$disks_dir" ]]; then
        return 0
    fi
    
    find "$disks_dir" -name "*.qcow2" -type f 2>/dev/null | sort
}

list_vdc_cloud_init_isos() {
    local vdc_name="$1"
    local cloud_init_dir=$(get_vdc_cloud_init_dir "$vdc_name")
    
    if [[ ! -d "$cloud_init_dir" ]]; then
        return 0
    fi
    
    find "$cloud_init_dir" -name "*.iso" -type f 2>/dev/null | sort
}

list_vdc_bgp_configs() {
    local vdc_name="$1"
    local bgp_configs_dir=$(get_vdc_bgp_configs_dir "$vdc_name")
    
    if [[ ! -d "$bgp_configs_dir" ]]; then
        return 0
    fi
    
    find "$bgp_configs_dir" -name "*.conf" -type f 2>/dev/null | sort
}

list_vdc_network_xmls() {
    local vdc_name="$1"
    local network_xmls_dir=$(get_vdc_network_xmls_dir "$vdc_name")
    
    if [[ ! -d "$network_xmls_dir" ]]; then
        return 0
    fi
    
    find "$network_xmls_dir" -name "*.xml" -type f 2>/dev/null | sort
}

count_vdc_disks() {
    local vdc_name="$1"
    list_vdc_disks "$vdc_name" | wc -l | tr -d ' '
}

count_vdc_cloud_init_isos() {
    local vdc_name="$1"
    list_vdc_cloud_init_isos "$vdc_name" | wc -l | tr -d ' '
}

count_vdc_bgp_configs() {
    local vdc_name="$1"
    list_vdc_bgp_configs "$vdc_name" | wc -l | tr -d ' '
}

count_vdc_network_xmls() {
    local vdc_name="$1"
    list_vdc_network_xmls "$vdc_name" | wc -l | tr -d ' '
}

################################################################################
# Resource Removal Functions
################################################################################

remove_vdc_disk() {
    local vdc_name="$1"
    local vm_name="$2"
    local disk_path=$(get_vdc_disk_path "$vdc_name" "$vm_name")
    
    if [[ -f "$disk_path" ]]; then
        rm -f "$disk_path"
        log_info "Removed disk: $disk_path"
        return 0
    else
        log_warn "Disk not found: $disk_path"
        return 1
    fi
}

remove_vdc_cloud_init_iso() {
    local vdc_name="$1"
    local vm_name="$2"
    local iso_path=$(get_vdc_cloud_init_iso "$vdc_name" "$vm_name")
    local vm_dir=$(get_vdc_cloud_init_vm_dir "$vdc_name" "$vm_name")
    
    if [[ -f "$iso_path" ]]; then
        rm -f "$iso_path"
        log_info "Removed cloud-init ISO: $iso_path"
    fi
    
    if [[ -d "$vm_dir" ]]; then
        rm -rf "$vm_dir"
        log_info "Removed cloud-init directory: $vm_dir"
    fi
    
    return 0
}

remove_vdc_bgp_config() {
    local vdc_name="$1"
    local device_name="$2"
    local bgp_config=$(get_vdc_bgp_config_file "$vdc_name" "$device_name")
    
    if [[ -f "$bgp_config" ]]; then
        rm -f "$bgp_config"
        log_info "Removed BGP config: $bgp_config"
        return 0
    else
        log_warn "BGP config not found: $bgp_config"
        return 1
    fi
}

remove_vdc_network_xml() {
    local vdc_name="$1"
    local network_name="$2"
    local network_xml=$(get_vdc_network_xml "$vdc_name" "$network_name")
    
    if [[ -f "$network_xml" ]]; then
        rm -f "$network_xml"
        log_info "Removed network XML: $network_xml"
        return 0
    else
        log_warn "Network XML not found: $network_xml"
        return 1
    fi
}

remove_vdc_ssh_keys() {
    local vdc_name="$1"
    local ssh_keys_dir=$(get_vdc_ssh_keys_dir "$vdc_name")
    
    if [[ -d "$ssh_keys_dir" ]]; then
        rm -rf "$ssh_keys_dir"
        log_info "Removed SSH keys directory: $ssh_keys_dir"
        return 0
    else
        log_warn "SSH keys directory not found: $ssh_keys_dir"
        return 1
    fi
}

################################################################################
# Summary Functions
################################################################################

print_vdc_summary() {
    local vdc_name="$1"
    local base_dir=$(get_vdc_base_dir "$vdc_name")
    
    if [[ ! -d "$base_dir" ]]; then
        echo "VDC '$vdc_name' directory does not exist"
        return 1
    fi
    
    local total_size=$(get_vdc_total_disk_usage "$vdc_name")
    local disk_count=$(count_vdc_disks "$vdc_name")
    local iso_count=$(count_vdc_cloud_init_isos "$vdc_name")
    local bgp_count=$(count_vdc_bgp_configs "$vdc_name")
    local xml_count=$(count_vdc_network_xmls "$vdc_name")
    
    echo "═══════════════════════════════════════════════════════════"
    echo "  VDC Resource Summary: $vdc_name"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Base Directory:      $base_dir"
    echo "Total Size:          $total_size"
    echo ""
    echo "Resource Counts:"
    echo "  VM Disks:          $disk_count"
    echo "  Cloud-init ISOs:   $iso_count"
    echo "  BGP Configs:       $bgp_count"
    echo "  Network XMLs:      $xml_count"
    echo "  SSH Keys:          $(vdc_ssh_keys_exist "$vdc_name" && echo "Present" || echo "Not found")"
    echo ""
}

################################################################################
# Backup and Export Functions
################################################################################

get_vdc_backup_name() {
    local vdc_name="$1"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    echo "vdc-${vdc_name}-backup-${timestamp}.tar.gz"
}

backup_vdc() {
    local vdc_name="$1"
    local backup_dir="${2:-$PROJECT_ROOT/backups}"
    local base_dir=$(get_vdc_base_dir "$vdc_name")
    
    if [[ ! -d "$base_dir" ]]; then
        log_error "VDC directory not found: $base_dir"
        return 1
    fi
    
    mkdir -p "$backup_dir"
    
    local backup_file="$backup_dir/$(get_vdc_backup_name "$vdc_name")"
    
    log_info "Creating backup of VDC '$vdc_name'..."
    tar -czf "$backup_file" -C "$(dirname "$base_dir")" "$(basename "$base_dir")"
    
    if [[ $? -eq 0 ]]; then
        local backup_size=$(du -h "$backup_file" | cut -f1)
        log_success "✓ Backup created: $backup_file ($backup_size)"
        echo "$backup_file"
        return 0
    else
        log_error "Failed to create backup"
        return 1
    fi
}

restore_vdc_from_backup() {
    local backup_file="$1"
    local restore_dir="${2:-$PROJECT_ROOT/config}"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    log_info "Restoring VDC from backup: $backup_file"
    tar -xzf "$backup_file" -C "$restore_dir"
    
    if [[ $? -eq 0 ]]; then
        log_success "✓ VDC restored from backup"
        return 0
    else
        log_error "Failed to restore VDC from backup"
        return 1
    fi
}
