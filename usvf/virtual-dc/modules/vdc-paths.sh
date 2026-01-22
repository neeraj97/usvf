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
    local base_dir=$(get_vdc_base_dir "$vdc_name")"
    
    if [[ ! -d "$base_dir" ]]; then
        log_error "VDC directory not found: $base_dir"
        return 1
    fi
    
    echo "VDC Resources for: $vdc_name"
    echo "Base directory: $base_dir"
    echo ""
    
    echo "Disks:"
    find "$(get_vdc_disks_dir "$vdc_name")" -name "*.qcow2" 2>/dev/null | while read disk; do
        local size=$(du -h "$disk" | cut -f1)
        echo "  $disk ($size)"
    done
    echo ""
    
    echo "Cloud-init ISOs:"
    find "$(get_vdc_cloud_init_dir "$vdc_name")" -name "*.iso" 2>/dev/null | while read iso; do
        local size=$(du -h "$iso" | cut -f1)
        echo "  $iso ($size)"
    done
    echo ""
    
    echo "BGP Configs:"
    find "$(get_vdc_bgp_configs_dir "$vdc_name")" -name "*.conf" 2>/dev/null | while read conf; do
        echo "  $conf"
    done
    echo ""
    
    echo "Network XMLs:"
    find "$(get_vdc_network_xmls_dir "$vdc_name")" -name "*.xml" 2>/dev/null | while read xml; do
        echo "  $xml"
    done
    echo ""
    
    echo "SSH Keys:"
    find "$(get_vdc_ssh_keys_dir "$vdc_name")" -type f 2>/dev/null | while read key; do
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
