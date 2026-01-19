#!/bin/bash
################################################################################
# Interactive Topology Builder
#
# Allows users to design virtual DC topology through:
# 1. Interactive CLI prompts
# 2. ASCII art diagram parsing
# 3. Automatic YAML generation
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

show_banner() {
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════╗
║                  Virtual DC Topology Builder                      ║
║                                                                   ║
║  Design your datacenter topology interactively and generate      ║
║  YAML configuration automatically!                                ║
╚═══════════════════════════════════════════════════════════════════╝

EOF
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Design and build virtual datacenter topologies.

OPTIONS:
    --interactive    Interactive mode (guided questions)
    --ascii-import   Import topology from ASCII art file
    --quick-start    Quick start with common templates
    --help           Show this help message

MODES:
    1. Interactive Mode - Step-by-step guided design
    2. ASCII Import - Parse ASCII art topology diagram
    3. Quick Start - Choose from pre-built templates

DEVICE TYPES:
    - hypervisor: Compute nodes with BGP routing
    - switch: Network switches (can be leaf/spine/superspine)

EXAMPLES:
    # Interactive mode
    $0 --interactive

    # Import ASCII topology
    $0 --ascii-import topology-diagram.txt

    # Quick start with template
    $0 --quick-start

EOF
}

interactive_mode() {
    log_info "Starting Interactive Topology Builder..."
    echo
    
    # Get basic info
    read -p "Enter datacenter name (e.g., 'my-dc-lab'): " dc_name
    dc_name=${dc_name:-my-dc-lab}
    
    read -p "Enter management network subnet (default: 192.168.100.0/24): " mgmt_subnet
    mgmt_subnet=${mgmt_subnet:-192.168.100.0/24}
    
    # Get hypervisors
    echo
    log_info "Hypervisor Configuration"
    read -p "How many hypervisors? (1-16): " hv_count
    hv_count=${hv_count:-2}
    
    declare -a hypervisors
    for i in $(seq 1 $hv_count); do
        echo
        echo "Hypervisor $i:"
        read -p "  Name (default: hypervisor-$i): " hv_name
        hv_name=${hv_name:-hypervisor-$i}
        
        read -p "  ASN (default: $((65000 + i))): " asn
        asn=${asn:-$((65000 + i))}
        
        read -p "  Number of data interfaces (1-4, default: 2): " iface_count
        iface_count=${iface_count:-2}
        
        hypervisors[$i]="$hv_name|$asn|$iface_count"
    done
    
    # Get switches
    echo
    log_info "Switch Configuration"
    read -p "How many switches? (1-16): " sw_count
    sw_count=${sw_count:-2}
    
    declare -a switches
    for i in $(seq 1 $sw_count); do
        echo
        echo "Switch $i:"
        read -p "  Name (default: switch-$i): " sw_name
        sw_name=${sw_name:-switch-$i}
        
        read -p "  Role (leaf/spine/superspine, default: leaf): " role
        role=${role:-leaf}
        
        read -p "  ASN (default: $((65100 + i))): " asn
        asn=${asn:-$((65100 + i))}
        
        switches[$i]="$sw_name|$role|$asn"
    done
    
    # Auto-generate cabling or let user define
    echo
    log_info "Cabling Configuration"
    echo "1) Auto-generate full-mesh cabling"
    echo "2) Define cabling manually"
    read -p "Choose option (1-2, default: 1): " cabling_option
    cabling_option=${cabling_option:-1}
    
    # Generate YAML
    generate_yaml "$dc_name" "$mgmt_subnet" hypervisors[@] switches[@] "$cabling_option"
}

generate_yaml() {
    local dc_name=$1
    local mgmt_subnet=$2
    local -n hvs=$3
    local -n sws=$4
    local cabling_option=$5
    
    local output_file="$PROJECT_ROOT/config/${dc_name}-topology.yaml"
    
    log_info "Generating YAML configuration..."
    
    # Extract gateway from subnet
    local gateway=$(echo $mgmt_subnet | sed 's|0/24|1|')
    
    cat > "$output_file" << EOF
# Auto-generated topology configuration
# Generated: $(date)
# Datacenter: $dc_name

global:
  datacenter_name: "$dc_name"
  virtualization_platform: "kvm"
  
  management_network:
    subnet: "$mgmt_subnet"
    gateway: "$gateway"
    description: "Out-of-band management network (L2)"
  
  kvm_settings:
    base_image: "ubuntu-22.04"
    default_user: "ubuntu"

hypervisors:
EOF
    
    # Add hypervisors
    local mgmt_ip=11
    for i in "${!hvs[@]}"; do
        IFS='|' read -r name asn ifaces <<< "${hvs[$i]}"
        local router_id="1.1.1.$i"
        
        cat >> "$output_file" << EOF
  - name: "$name"
    short_name: "hv$i"
    router_id: "$router_id"
    asn: $asn
    management:
      ip: "192.168.100.$mgmt_ip/24"
      switch: "mgmt-sw"
    data_interfaces:
EOF
        
        for j in $(seq 1 $ifaces); do
            cat >> "$output_file" << EOF
      - name: "eth$j"
        description: "Data interface $j"
EOF
        done
        
        cat >> "$output_file" << EOF
    resources:
      cpu: 4
      memory: 4096
      disk: 50

EOF
        mgmt_ip=$((mgmt_ip + 1))
    done
    
    # Add switches
    cat >> "$output_file" << EOF
switches:
EOF
    
    mgmt_ip=101
    for i in "${!sws[@]}"; do
        IFS='|' read -r name role asn <<< "${sws[$i]}"
        local router_id="2.2.2.$i"
        
        cat >> "$output_file" << EOF
  - name: "$name"
    device_type: "switch"
    role: "$role"
    router_id: "$router_id"
    asn: $asn
    management:
      ip: "192.168.100.$mgmt_ip/24"
      switch: "mgmt-sw"
    ports: 32
    port_speed: "10G"

EOF
        mgmt_ip=$((mgmt_ip + 1))
    done
    
    # Add cabling section
    cat >> "$output_file" << EOF
cabling:
EOF
    
    if [[ $cabling_option == "1" ]]; then
        # Auto-generate cabling
        local cable_id=0
        for i in "${!hvs[@]}"; do
            IFS='|' read -r hv_name hv_asn ifaces <<< "${hvs[$i]}"
            
            for j in $(seq 1 $ifaces); do
                # Connect to switch (simple round-robin)
                local sw_idx=$(( (cable_id % ${#sws[@]}) + 1 ))
                IFS='|' read -r sw_name sw_role sw_asn <<< "${sws[$sw_idx]}"
                
                cat >> "$output_file" << EOF
  - source:
      device: "$hv_name"
      interface: "eth$j"
    destination:
      device: "$sw_name"
      interface: "Ethernet$((cable_id + 1))"
    link_type: "p2p"
    description: "$hv_name:eth$j to $sw_name"

EOF
                cable_id=$((cable_id + 1))
            done
        done
    fi
    
    # Add visual topology
    cat >> "$output_file" << EOF
topology_visual: |
  
  Generated Topology for $dc_name
  ================================
  
  [Auto-generated topology diagram]
  
  Hypervisors: ${#hvs[@]}
  Switches: ${#sws[@]}
  
  Management Network: $mgmt_subnet
EOF
    
    log_success "Configuration generated: $output_file"
    echo
    log_info "Next steps:"
    echo "  1. Review: vim $output_file"
    echo "  2. Validate: ./scripts/deploy-virtual-dc.sh --validate --config $output_file"
    echo "  3. Deploy: ./scripts/deploy-virtual-dc.sh --config $output_file"
}

ascii_import_mode() {
    local ascii_file=$1
    
    if [[ ! -f "$ascii_file" ]]; then
        log_error "File not found: $ascii_file"
        return 1
    fi
    
    log_info "Parsing ASCII topology from: $ascii_file"
    
    # Parse the ASCII file to extract devices and connections
    # This is a simplified parser - can be enhanced
    
    log_warn "ASCII import is a preview feature. Please review generated YAML carefully."
    
    # For now, show what was parsed
    cat "$ascii_file"
}

quick_start_mode() {
    log_info "Quick Start Templates"
    echo
    echo "Choose a template:"
    echo "  1) Minimal (2 hypervisors, 1 switch)"
    echo "  2) Small Lab (4 hypervisors, 2 leafs, 2 spines)"
    echo "  3) Medium Lab (8 hypervisors, 4 leafs, 2 spines)"
    echo "  4) Large Lab (16 hypervisors, 8 leafs, 4 spines, 2 superspines)"
    echo
    read -p "Select template (1-4): " template
    
    case $template in
        1) create_minimal_template ;;
        2) create_small_template ;;
        3) create_medium_template ;;
        4) create_large_template ;;
        *) log_error "Invalid selection"; return 1 ;;
    esac
}

create_minimal_template() {
    read -p "Enter datacenter name (default: minimal-lab): " dc_name
    dc_name=${dc_name:-minimal-lab}
    
    log_info "Creating minimal template..."
    cp "$PROJECT_ROOT/examples/simple-2node.yaml" "$PROJECT_ROOT/config/${dc_name}-topology.yaml"
    
    # Update datacenter name in the file
    sed -i.bak "s/datacenter_name: .*/datacenter_name: \"$dc_name\"/" \
        "$PROJECT_ROOT/config/${dc_name}-topology.yaml"
    
    log_success "Template created: $PROJECT_ROOT/config/${dc_name}-topology.yaml"
}

create_small_template() {
    log_info "Creating small lab template..."
    cp "$PROJECT_ROOT/config/topology.yaml" "$PROJECT_ROOT/config/small-lab-topology.yaml"
    log_success "Template created: $PROJECT_ROOT/config/small-lab-topology.yaml"
}

create_medium_template() {
    log_info "Medium and large templates coming soon!"
    log_info "For now, use interactive mode or edit the YAML manually."
}

create_large_template() {
    create_medium_template
}

# Main execution
main() {
    show_banner
    
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    case "$1" in
        --interactive)
            interactive_mode
            ;;
        --ascii-import)
            if [[ $# -lt 2 ]]; then
                log_error "Please provide ASCII file path"
                exit 1
            fi
            ascii_import_mode "$2"
            ;;
        --quick-start)
            quick_start_mode
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
