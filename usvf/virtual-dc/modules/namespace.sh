#!/bin/bash
################################################################################
# Namespace Module - Network Namespace Management
#
# Provides functions for managing network namespaces for VDC isolation:
# - Namespace creation
# - Namespace destruction
# - Interface management within namespaces
# - Network isolation
################################################################################

# Ensure PROJECT_ROOT is set
: "${PROJECT_ROOT:?PROJECT_ROOT must be set}"

################################################################################
# Namespace Creation
################################################################################

create_vdc_namespace() {
    local namespace="$1"
    
    log_info "Creating network namespace: $namespace"
    
    # Check if namespace already exists
    if ip netns list 2>/dev/null | grep -q "^${namespace}"; then
        log_warn "Namespace '$namespace' already exists"
        return 0
    fi
    
    # Create namespace
    if ! sudo ip netns add "$namespace" 2>/dev/null; then
        log_error "Failed to create namespace: $namespace"
        return 1
    fi
    
    # Bring up loopback interface in namespace
    sudo ip netns exec "$namespace" ip link set lo up
    
    # Enable IP forwarding in namespace
    sudo ip netns exec "$namespace" sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
    sudo ip netns exec "$namespace" sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1
    
    log_success "Created namespace: $namespace"
    
    # Set up namespace directory for persistent storage
    local ns_dir="/var/run/netns"
    if [[ -d "$ns_dir" ]] && [[ -e "${ns_dir}/${namespace}" ]]; then
        log_success "Namespace is persistent at: ${ns_dir}/${namespace}"
    fi
}

################################################################################
# Namespace Destruction
################################################################################

destroy_vdc_namespace() {
    local namespace="$1"
    
    log_info "Destroying network namespace: $namespace"
    
    # Check if namespace exists
    if ! ip netns list 2>/dev/null | grep -q "^${namespace}"; then
        log_warn "Namespace '$namespace' does not exist"
        return 0
    fi
    
    # Delete all interfaces in the namespace first
    cleanup_namespace_interfaces "$namespace"
    
    # Delete namespace
    if ! sudo ip netns del "$namespace" 2>/dev/null; then
        log_error "Failed to delete namespace: $namespace"
        return 1
    fi
    
    log_success "Destroyed namespace: $namespace"
}

cleanup_namespace_interfaces() {
    local namespace="$1"
    
    log_info "Cleaning up interfaces in namespace: $namespace"
    
    # Get list of interfaces in namespace (excluding loopback)
    local interfaces=$(sudo ip netns exec "$namespace" ip link show 2>/dev/null | \
        grep -E "^[0-9]+: " | \
        awk -F': ' '{print $2}' | \
        cut -d'@' -f1 | \
        grep -v "^lo$" || true)
    
    if [[ -z "$interfaces" ]]; then
        log_info "No interfaces to clean up in namespace"
        return 0
    fi
    
    while IFS= read -r iface; do
        if [[ -n "$iface" ]]; then
            log_info "  Removing interface: $iface"
            sudo ip netns exec "$namespace" ip link delete "$iface" 2>/dev/null || true
        fi
    done <<< "$interfaces"
}

################################################################################
# Namespace Interface Management
################################################################################

create_veth_pair() {
    local veth_host="$1"
    local veth_ns="$2"
    local namespace="$3"
    
    log_info "Creating veth pair: $veth_host <-> $veth_ns (ns: $namespace)"
    
    # Create veth pair
    if ! sudo ip link add "$veth_host" type veth peer name "$veth_ns" 2>/dev/null; then
        log_error "Failed to create veth pair"
        return 1
    fi
    
    # Move one end to namespace
    if ! sudo ip link set "$veth_ns" netns "$namespace" 2>/dev/null; then
        log_error "Failed to move interface to namespace"
        # Cleanup
        sudo ip link delete "$veth_host" 2>/dev/null || true
        return 1
    fi
    
    # Bring up both interfaces
    sudo ip link set "$veth_host" up
    sudo ip netns exec "$namespace" ip link set "$veth_ns" up
    
    log_success "Created veth pair: $veth_host <-> $veth_ns"
}

delete_veth_pair() {
    local veth_host="$1"
    
    log_info "Deleting veth pair: $veth_host"
    
    # Deleting one end automatically deletes the pair
    sudo ip link delete "$veth_host" 2>/dev/null || true
    
    log_success "Deleted veth pair"
}

################################################################################
# Bridge Management in Namespace
################################################################################

create_bridge_in_namespace() {
    local namespace="$1"
    local bridge_name="$2"
    local ip_addr="${3:-}"
    
    log_info "Creating bridge in namespace: $bridge_name (ns: $namespace)"
    
    # Create bridge
    sudo ip netns exec "$namespace" ip link add name "$bridge_name" type bridge
    
    # Set bridge parameters
    sudo ip netns exec "$namespace" ip link set "$bridge_name" up
    
    # Assign IP if provided
    if [[ -n "$ip_addr" ]]; then
        sudo ip netns exec "$namespace" ip addr add "$ip_addr" dev "$bridge_name"
        log_info "Assigned IP $ip_addr to bridge $bridge_name"
    fi
    
    log_success "Created bridge: $bridge_name in namespace $namespace"
}

attach_interface_to_bridge() {
    local namespace="$1"
    local interface="$2"
    local bridge="$3"
    
    log_info "Attaching interface $interface to bridge $bridge (ns: $namespace)"
    
    # Attach interface to bridge
    sudo ip netns exec "$namespace" ip link set "$interface" master "$bridge"
    sudo ip netns exec "$namespace" ip link set "$interface" up
    
    log_success "Attached $interface to bridge $bridge"
}

################################################################################
# NAT Configuration for Namespace
################################################################################

setup_namespace_nat() {
    local namespace="$1"
    local internal_subnet="$2"
    local external_interface="${3:-eth0}"
    
    log_info "Setting up NAT for namespace: $namespace"
    log_info "  Internal subnet: $internal_subnet"
    log_info "  External interface: $external_interface"
    
    # Enable masquerading for outbound traffic
    sudo ip netns exec "$namespace" iptables -t nat -A POSTROUTING \
        -s "$internal_subnet" -o "$external_interface" -j MASQUERADE
    
    # Allow forwarding
    sudo ip netns exec "$namespace" iptables -A FORWARD -i "$external_interface" \
        -o "$external_interface" -j ACCEPT
    sudo ip netns exec "$namespace" iptables -A FORWARD -i "$external_interface" \
        -o "$external_interface" -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    log_success "NAT configured for namespace: $namespace"
}

################################################################################
# Namespace Information
################################################################################

list_namespace_interfaces() {
    local namespace="$1"
    
    echo "Interfaces in namespace '$namespace':"
    sudo ip netns exec "$namespace" ip addr show 2>/dev/null || echo "  (namespace not found)"
}

show_namespace_routes() {
    local namespace="$1"
    
    echo "Routes in namespace '$namespace':"
    sudo ip netns exec "$namespace" ip route show 2>/dev/null || echo "  (namespace not found)"
}

show_namespace_iptables() {
    local namespace="$1"
    
    echo "iptables in namespace '$namespace':"
    sudo ip netns exec "$namespace" iptables -L -n -v 2>/dev/null || echo "  (namespace not found)"
}

################################################################################
# Namespace Validation
################################################################################

validate_namespace() {
    local namespace="$1"
    
    log_info "Validating namespace: $namespace"
    
    # Check if namespace exists
    if ! ip netns list 2>/dev/null | grep -q "^${namespace}"; then
        log_error "Namespace does not exist: $namespace"
        return 1
    fi
    
    # Check loopback
    if ! sudo ip netns exec "$namespace" ip link show lo 2>/dev/null | grep -q "state UP"; then
        log_warn "Loopback interface is not UP in namespace"
    fi
    
    # Check IP forwarding
    local ipv4_forward=$(sudo ip netns exec "$namespace" sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
    if [[ "$ipv4_forward" != "1" ]]; then
        log_warn "IPv4 forwarding is disabled in namespace"
    fi
    
    log_success "Namespace validation completed"
}

################################################################################
# Namespace Connectivity Test
################################################################################

test_namespace_connectivity() {
    local namespace="$1"
    local target_ip="${2:-8.8.8.8}"
    
    log_info "Testing connectivity from namespace: $namespace"
    
    if sudo ip netns exec "$namespace" ping -c 1 -W 2 "$target_ip" >/dev/null 2>&1; then
        log_success "Connectivity test passed (pinged $target_ip)"
        return 0
    else
        log_warn "Connectivity test failed (could not ping $target_ip)"
        return 1
    fi
}

################################################################################
# Execute Command in Namespace
################################################################################

exec_in_namespace() {
    local namespace="$1"
    shift
    local command="$@"
    
    sudo ip netns exec "$namespace" $command
}

################################################################################
# Namespace Statistics
################################################################################

show_namespace_stats() {
    local namespace="$1"
    
    echo "═══════════════════════════════════════════════════════════"
    echo "Statistics for namespace: $namespace"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    
    if ! ip netns list 2>/dev/null | grep -q "^${namespace}"; then
        echo "Namespace not found"
        return 1
    fi
    
    echo "Network Interfaces:"
    echo "-------------------"
    sudo ip netns exec "$namespace" ip -br link show
    echo ""
    
    echo "IP Addresses:"
    echo "-------------"
    sudo ip netns exec "$namespace" ip -br addr show
    echo ""
    
    echo "Routing Table:"
    echo "--------------"
    sudo ip netns exec "$namespace" ip route show
    echo ""
    
    echo "ARP Table:"
    echo "----------"
    sudo ip netns exec "$namespace" ip neigh show
    echo ""
    
    echo "Network Statistics:"
    echo "-------------------"
    sudo ip netns exec "$namespace" ip -s link show | grep -A1 "RX:\|TX:"
    echo ""
}

################################################################################
# Namespace Cleanup Utilities
################################################################################

cleanup_all_vdc_namespaces() {
    log_info "Cleaning up all VDC namespaces..."
    
    local vdc_namespaces=$(ip netns list 2>/dev/null | grep "^vdc-" | awk '{print $1}' || true)
    
    if [[ -z "$vdc_namespaces" ]]; then
        log_info "No VDC namespaces found"
        return 0
    fi
    
    local count=0
    while IFS= read -r ns; do
        if [[ -n "$ns" ]]; then
            log_info "  Removing namespace: $ns"
            destroy_vdc_namespace "$ns"
            count=$((count + 1))
        fi
    done <<< "$vdc_namespaces"
    
    log_success "Cleaned up $count VDC namespaces"
}

list_all_namespaces() {
    echo "All network namespaces:"
    ip netns list 2>/dev/null || echo "  (none)"
}

################################################################################
# Namespace Process Management
################################################################################

list_namespace_processes() {
    local namespace="$1"
    
    log_info "Processes running in namespace: $namespace"
    
    # Get namespace inode
    local ns_inode=$(sudo ip netns identify $$ 2>/dev/null || echo "")
    
    if [[ -z "$ns_inode" ]]; then
        # Alternative method: check all processes
        echo "Searching for processes in namespace..."
        sudo lsns -t net | grep "$namespace" || echo "  (none found)"
    fi
}

kill_namespace_processes() {
    local namespace="$1"
    
    log_warn "Terminating all processes in namespace: $namespace"
    
    # Find PIDs in namespace
    local pids=$(sudo ip netns pids "$namespace" 2>/dev/null || true)
    
    if [[ -z "$pids" ]]; then
        log_info "No processes found in namespace"
        return 0
    fi
    
    # Kill processes
    while IFS= read -r pid; do
        if [[ -n "$pid" ]]; then
            log_info "  Killing process: $pid"
            sudo kill -9 "$pid" 2>/dev/null || true
        fi
    done <<< "$pids"
    
    log_success "Terminated processes in namespace: $namespace"
}

################################################################################
# Namespace Backup/Restore
################################################################################

export_namespace_config() {
    local namespace="$1"
    local output_file="$2"
    
    log_info "Exporting namespace configuration: $namespace -> $output_file"
    
    {
        echo "# Namespace: $namespace"
        echo "# Exported: $(date)"
        echo ""
        echo "# Interfaces"
        sudo ip netns exec "$namespace" ip addr show
        echo ""
        echo "# Routes"
        sudo ip netns exec "$namespace" ip route show
        echo ""
        echo "# iptables"
        sudo ip netns exec "$namespace" iptables-save
    } > "$output_file"
    
    log_success "Configuration exported to: $output_file"
}

################################################################################
# Namespace Security
################################################################################

isolate_namespace() {
    local namespace="$1"
    
    log_info "Applying security isolation to namespace: $namespace"
    
    # Drop all forwarding by default
    sudo ip netns exec "$namespace" iptables -P FORWARD DROP
    
    # Drop all input by default (except established)
    sudo ip netns exec "$namespace" iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    sudo ip netns exec "$namespace" iptables -A INPUT -i lo -j ACCEPT
    sudo ip netns exec "$namespace" iptables -P INPUT DROP
    
    log_success "Security isolation applied to namespace: $namespace"
}

################################################################################
# Helper Functions
################################################################################

namespace_exists() {
    local namespace="$1"
    ip netns list 2>/dev/null | grep -q "^${namespace}"
}

get_namespace_id() {
    local namespace="$1"
    
    if [[ -e "/var/run/netns/${namespace}" ]]; then
        stat -c %i "/var/run/netns/${namespace}" 2>/dev/null || echo "unknown"
    else
        echo "not found"
    fi
}

count_namespace_interfaces() {
    local namespace="$1"
    
    sudo ip netns exec "$namespace" ip link show 2>/dev/null | \
        grep -c "^[0-9]" || echo "0"
}
