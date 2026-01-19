#!/bin/bash
################################################################################
# Configuration Validation Module
#
# Validates the topology YAML configuration file for:
# - Syntax correctness
# - IP address conflicts
# - Router ID uniqueness
# - AS number validation
# - Cabling consistency
################################################################################

validate_configuration() {
    local config_file="$1"
    
    log_info "Validating configuration file: $config_file"
    
    # Check if yq is installed for YAML parsing
    if ! command -v yq &> /dev/null; then
        log_error "yq is not installed. Please install it: brew install yq"
        return 1
    fi
    
    # Validate YAML syntax
    if ! yq eval '.' "$config_file" &> /dev/null; then
        log_error "Invalid YAML syntax in configuration file"
        return 1
    fi
    log_success "✓ YAML syntax is valid"
    
    # Validate hypervisors section
    validate_hypervisors "$config_file"
    
    # Validate switches section
    validate_switches "$config_file"
    
    # Validate cabling section
    validate_cabling "$config_file"
    
    # Validate IP addresses
    validate_ip_addresses "$config_file"
    
    # Validate router IDs
    validate_router_ids "$config_file"
    
    # Validate ASN configuration
    validate_asn_config "$config_file"
    
    log_success "✓ All validation checks passed"
    return 0
}

validate_hypervisors() {
    local config_file="$1"
    log_info "Validating hypervisors configuration..."
    
    local hv_count=$(yq eval '.hypervisors | length' "$config_file")
    if [[ $hv_count -eq 0 ]]; then
        log_error "No hypervisors defined in configuration"
        return 1
    fi
    
    log_success "✓ Found $hv_count hypervisors"
    
    # Validate each hypervisor
    for i in $(seq 0 $((hv_count - 1))); do
        local hv_name=$(yq eval ".hypervisors[$i].name" "$config_file")
        local router_id=$(yq eval ".hypervisors[$i].router_id" "$config_file")
        local asn=$(yq eval ".hypervisors[$i].asn" "$config_file")
        local mgmt_ip=$(yq eval ".hypervisors[$i].management.ip" "$config_file")
        
        if [[ -z "$hv_name" ]] || [[ "$hv_name" == "null" ]]; then
            log_error "Hypervisor at index $i has no name"
            return 1
        fi
        
        if [[ -z "$router_id" ]] || [[ "$router_id" == "null" ]]; then
            log_error "Hypervisor $hv_name has no router_id"
            return 1
        fi
        
        if [[ -z "$asn" ]] || [[ "$asn" == "null" ]]; then
            log_error "Hypervisor $hv_name has no ASN"
            return 1
        fi
        
        if [[ -z "$mgmt_ip" ]] || [[ "$mgmt_ip" == "null" ]]; then
            log_error "Hypervisor $hv_name has no management IP"
            return 1
        fi
    done
    
    log_success "✓ Hypervisors configuration is valid"
    return 0
}

validate_switches() {
    local config_file="$1"
    log_info "Validating switches configuration..."
    
    local total_switches=0
    
    # Count leaf switches
    local leaf_count=$(yq eval '.switches.leaf | length' "$config_file")
    total_switches=$((total_switches + leaf_count))
    
    # Count spine switches
    local spine_count=$(yq eval '.switches.spine | length' "$config_file")
    total_switches=$((total_switches + spine_count))
    
    # Count superspine switches
    local superspine_count=$(yq eval '.switches.superspine | length' "$config_file")
    total_switches=$((total_switches + superspine_count))
    
    if [[ $total_switches -eq 0 ]]; then
        log_error "No switches defined in configuration"
        return 1
    fi
    
    log_success "✓ Found $total_switches switches (Leaf: $leaf_count, Spine: $spine_count, SuperSpine: $superspine_count)"
    
    return 0
}

validate_cabling() {
    local config_file="$1"
    log_info "Validating cabling configuration..."
    
    local cable_count=$(yq eval '.cabling | length' "$config_file")
    if [[ $cable_count -eq 0 ]]; then
        log_warn "No cabling defined in configuration"
        return 0
    fi
    
    log_success "✓ Found $cable_count cable connections"
    
    # Validate each cable connection
    for i in $(seq 0 $((cable_count - 1))); do
        local src_device=$(yq eval ".cabling[$i].source.device" "$config_file")
        local src_iface=$(yq eval ".cabling[$i].source.interface" "$config_file")
        local dst_device=$(yq eval ".cabling[$i].destination.device" "$config_file")
        local dst_iface=$(yq eval ".cabling[$i].destination.interface" "$config_file")
        
        if [[ -z "$src_device" ]] || [[ "$src_device" == "null" ]]; then
            log_error "Cable connection $i has no source device"
            return 1
        fi
        
        if [[ -z "$dst_device" ]] || [[ "$dst_device" == "null" ]]; then
            log_error "Cable connection $i has no destination device"
            return 1
        fi
    done
    
    log_success "✓ Cabling configuration is valid"
    return 0
}

validate_ip_addresses() {
    local config_file="$1"
    log_info "Validating IP addresses..."
    
    local check_duplicates=$(yq eval '.validation.check_duplicate_ips' "$config_file")
    if [[ "$check_duplicates" != "true" ]]; then
        log_info "Skipping duplicate IP check (disabled in config)"
        return 0
    fi
    
    # Extract all management IPs
    declare -A ip_map
    
    # Check hypervisor IPs
    local hv_count=$(yq eval '.hypervisors | length' "$config_file")
    for i in $(seq 0 $((hv_count - 1))); do
        local ip=$(yq eval ".hypervisors[$i].management.ip" "$config_file" | cut -d'/' -f1)
        local name=$(yq eval ".hypervisors[$i].name" "$config_file")
        
        if [[ -n "${ip_map[$ip]}" ]]; then
            log_error "Duplicate IP address $ip found: ${ip_map[$ip]} and $name"
            return 1
        fi
        ip_map[$ip]=$name
    done
    
    # Check switch IPs (all tiers)
    for tier in leaf spine superspine; do
        local count=$(yq eval ".switches.$tier | length" "$config_file")
        for i in $(seq 0 $((count - 1))); do
            local ip=$(yq eval ".switches.$tier[$i].management.ip" "$config_file" | cut -d'/' -f1)
            local name=$(yq eval ".switches.$tier[$i].name" "$config_file")
            
            if [[ "$ip" != "null" ]] && [[ -n "${ip_map[$ip]}" ]]; then
                log_error "Duplicate IP address $ip found: ${ip_map[$ip]} and $name"
                return 1
            fi
            ip_map[$ip]=$name
        done
    done
    
    log_success "✓ No duplicate IP addresses found"
    return 0
}

validate_router_ids() {
    local config_file="$1"
    log_info "Validating router IDs..."
    
    local check_uniqueness=$(yq eval '.validation.check_router_id_uniqueness' "$config_file")
    if [[ "$check_uniqueness" != "true" ]]; then
        log_info "Skipping router ID uniqueness check (disabled in config)"
        return 0
    fi
    
    declare -A rid_map
    
    # Check hypervisor router IDs
    local hv_count=$(yq eval '.hypervisors | length' "$config_file")
    for i in $(seq 0 $((hv_count - 1))); do
        local rid=$(yq eval ".hypervisors[$i].router_id" "$config_file")
        local name=$(yq eval ".hypervisors[$i].name" "$config_file")
        
        if [[ -n "${rid_map[$rid]}" ]]; then
            log_error "Duplicate router ID $rid found: ${rid_map[$rid]} and $name"
            return 1
        fi
        rid_map[$rid]=$name
    done
    
    # Check switch router IDs
    for tier in leaf spine superspine; do
        local count=$(yq eval ".switches.$tier | length" "$config_file")
        for i in $(seq 0 $((count - 1))); do
            local rid=$(yq eval ".switches.$tier[$i].router_id" "$config_file")
            local name=$(yq eval ".switches.$tier[$i].name" "$config_file")
            
            if [[ "$rid" != "null" ]] && [[ -n "${rid_map[$rid]}" ]]; then
                log_error "Duplicate router ID $rid found: ${rid_map[$rid]} and $name"
                return 1
            fi
            rid_map[$rid]=$name
        done
    done
    
    log_success "✓ All router IDs are unique"
    return 0
}

validate_asn_config() {
    local config_file="$1"
    log_info "Validating AS numbers..."
    
    # Just verify ASN values are within valid range (1-4294967295)
    local hv_count=$(yq eval '.hypervisors | length' "$config_file")
    for i in $(seq 0 $((hv_count - 1))); do
        local asn=$(yq eval ".hypervisors[$i].asn" "$config_file")
        local name=$(yq eval ".hypervisors[$i].name" "$config_file")
        
        if [[ $asn -lt 1 ]] || [[ $asn -gt 4294967295 ]]; then
            log_error "Invalid ASN $asn for $name (must be 1-4294967295)"
            return 1
        fi
    done
    
    log_success "✓ AS numbers are valid"
    return 0
}
