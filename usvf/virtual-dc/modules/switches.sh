#!/bin/bash
################################################################################
# FRR Switch Deployment Module
#
# Deploys and configures FRR switch VMs with:
# - Ubuntu 24.04 VMs as switch hosts
# - FRRouting (FRR) for BGP routing
# - BGP unnumbered configuration
# - Multiple network interfaces
# - Management interface configuration
#
# Method: FRR running natively on Ubuntu VMs (no containers)
################################################################################

deploy_switches() {
    local config_file="$1"
    local dry_run="${2:-false}"
    
    log_info "=========================================="
    log_info "DEPLOYING FRR SWITCHES"
    log_info "=========================================="
    log_info "Method: Ubuntu 24.04 VMs + FRRouting"
    log_info "BGP: Unnumbered with IPv6 link-local"
    log_info ""
    
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
    
    log_success "✓ All FRR switch VMs deployed successfully"
    log_info "Note: FRR will configure BGP automatically after VMs boot"
    log_info "Access switches via: ssh ubuntu@<switch-mgmt-ip>"
    log_info "Access FRR CLI: vtysh"
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
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local router_id=$(yq eval ".switches.$tier[$index].router_id" "$config_file")
    local asn=$(yq eval ".switches.$tier[$index].asn" "$config_file")
    local mgmt_ip=$(yq eval ".switches.$tier[$index].management.ip" "$config_file")
    local iface_count=$(yq eval ".switches.$tier[$index].data_interfaces | length" "$config_file")
    local cpu=$(yq eval ".switches.$tier[$index].resources.cpu" "$config_file")
    local memory=$(yq eval ".switches.$tier[$index].resources.memory" "$config_file")

    # Create full VM name with DC prefix for proper isolation
    local full_vm_name="${dc_name}-${sw_name}"

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Deploying $tier switch: $full_vm_name"
    log_info "  Hostname: $sw_name"
    log_info "  Router ID: $router_id"
    log_info "  ASN: $asn"
    log_info "  Management IP: $mgmt_ip"
    log_info "  Data Interfaces: $iface_count"
    log_info "  Resources: ${cpu} vCPU, ${memory}MB RAM"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would create FRR switch VM: $full_vm_name"
        return 0
    fi

    # Step 1: Create cloud-init configuration for Ubuntu VM (use original sw_name for hostname)
    create_sonic_cloud_init "$config_file" "$tier" "$index" "$sw_name" "$full_vm_name"

    # Step 2: Create VM disk (use full_vm_name for disk file)
    create_sonic_disk "$config_file" "$full_vm_name"

    # Step 3: Create and start Ubuntu VM that will run FRR (use full_vm_name for VM name)
    create_sonic_vm "$config_file" "$tier" "$index" "$full_vm_name" "$sw_name" "$cpu" "$memory" "$iface_count"

    log_success "✓ FRR switch VM $full_vm_name deployed (FRR will auto-configure)"
}

create_sonic_cloud_init() {
    local config_file="$1"
    local tier="$2"
    local index="$3"
    local sw_name="$4"
    local full_vm_name="$5"

    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local ssh_key_path=$(get_vdc_ssh_public_key "$dc_name")
    local ssh_pubkey=$(cat "$ssh_key_path")

    local router_id=$(yq eval ".switches.$tier[$index].router_id" "$config_file")
    local asn=$(yq eval ".switches.$tier[$index].asn" "$config_file")
    local mgmt_ip=$(yq eval ".switches.$tier[$index].management.ip" "$config_file")
    local iface_count=$(yq eval ".switches.$tier[$index].data_interfaces | length" "$config_file")

    # Detect management network configuration from existing network
    local mgmt_config=$(get_management_network_config "$dc_name")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to detect management network configuration"
        return 1
    fi
    local mgmt_subnet=$(echo "$mgmt_config" | awk '{print $1}')
    local mgmt_gw=$(echo "$mgmt_config" | awk '{print $2}')

    local cloud_init_dir=$(get_vdc_cloud_init_vm_dir "$dc_name" "$full_vm_name")
    mkdir -p "$cloud_init_dir"

    log_info "Creating cloud-init configuration for $full_vm_name (Ubuntu with FRR)..."

    # Create user-data (matching hypervisor.sh exactly)
    cat > "$cloud_init_dir/user-data" <<EOF
#cloud-config
hostname: $sw_name
fqdn: ${sw_name}.local
manage_etc_hosts: true

users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $ssh_pubkey

packages:
  - frr
  - frr-pythontools
  - iproute2
  - net-tools
  - tcpdump
  - vim
  - curl

package_update: true
package_upgrade: true

write_files:
  - path: /etc/frr/daemons
    content: |
      zebra=yes
      bgpd=yes
      ospfd=no
      ospf6d=no
      ripd=no
      ripngd=no
      isisd=no
      pimd=no
      ldpd=no
      nhrpd=no
      eigrpd=no
      babeld=no
      sharpd=no
      pbrd=no
      bfdd=no
      fabricd=no
      vrrpd=no

      vtysh_enable=yes
      zebra_options="  -A 127.0.0.1 -s 90000000"
      bgpd_options="   -A 127.0.0.1"

  - path: /etc/frr/frr.conf
    content: |
      !
      ! FRRouting configuration for $sw_name
      ! Ubuntu 24.04 Noble Numbat
      ! Generated by Virtual DC Deployment Tool
      !
      frr version 10.0
      frr defaults traditional
      hostname $sw_name
      log syslog informational
      service integrated-vtysh-config
      !
      ! Configure loopback
      interface lo
       ip address $router_id/32
      !
      ! BGP Configuration with Unnumbered Support
      router bgp $asn
       bgp router-id $router_id
       bgp log-neighbor-changes
       bgp bestpath as-path multipath-relax
       no bgp default ipv4-unicast
       no bgp ebgp-requires-policy
       !
       ! Fabric peer-group for unnumbered BGP
       neighbor FABRIC peer-group
       neighbor FABRIC remote-as external
       neighbor FABRIC capability extended-nexthop
       !
EOF

    # Add BGP neighbors for each data interface (enp2s0, enp3s0, etc.)
    for i in $(seq 1 $iface_count); do
        local iface_name="enp$((i+1))s0"
        cat >> "$cloud_init_dir/user-data" <<EOF
       ! BGP neighbor on $iface_name
       neighbor $iface_name interface peer-group FABRIC
       !
EOF
    done

    cat >> "$cloud_init_dir/user-data" <<EOF
       address-family ipv4 unicast
        neighbor FABRIC activate
        maximum-paths 64
       exit-address-family
      !
      line vty
      !
      end
    permissions: '0640'
    owner: frr:frr

  - path: /etc/sysctl.d/99-forwarding.conf
    content: |
      net.ipv4.ip_forward=1
      net.ipv6.conf.all.forwarding=1

runcmd:
  - echo "Starting cloud-init setup for $sw_name..."
  - sysctl -p /etc/sysctl.d/99-forwarding.conf
EOF

    # Add commands to bring up data interfaces
    for i in $(seq 1 $iface_count); do
        local iface_name="enp$((i+1))s0"
        cat >> "$cloud_init_dir/user-data" <<EOF
  - ip link set $iface_name up
EOF
    done

    cat >> "$cloud_init_dir/user-data" <<EOF
  - chown frr:frr /etc/frr/frr.conf
  - chmod 640 /etc/frr/frr.conf
  - systemctl enable frr
  - systemctl restart frr
  - systemctl status frr --no-pager
  - |
    cat > /etc/motd <<'MOTD'
    ============================================================
    Ubuntu 24.04 LTS (Noble Numbat) - FRR Switch Node
    ============================================================
    Hostname:   $sw_name
    Router ID:  $router_id
    BGP ASN:    $asn
    Role:       Virtual DC Switch with BGP routing

    FRRouting:  Enabled (BGP Unnumbered support)

    Quick Commands:
      - vtysh               # Enter FRR CLI
      - show ip bgp summary # Check BGP status
      - show ip route       # View routing table
    ============================================================
    MOTD

power_state:
  mode: reboot
  timeout: 300
  condition: True
EOF

    # Create meta-data
    cat > "$cloud_init_dir/meta-data" <<EOF
instance-id: $sw_name
local-hostname: $sw_name
EOF

    # Create network-config
    local mgmt_ip_addr=$(echo "$mgmt_ip" | cut -d'/' -f1)
    local mgmt_prefix=$(echo "$mgmt_ip" | cut -d'/' -f2)
    
    cat > "$cloud_init_dir/network-config" <<EOF
version: 2
ethernets:
  enp1s0:
    dhcp4: false
    addresses:
      - $mgmt_ip
    routes:
      - to: 0.0.0.0/0
        via: $mgmt_gw
    nameservers:
      addresses:
        - 8.8.8.8
        - 8.8.4.4
EOF

    # Add data plane interfaces with IPv6 link-local for BGP unnumbered
    for i in $(seq 1 $iface_count); do
        local iface_name="enp$((i+1))s0"
        cat >> "$cloud_init_dir/network-config" <<EOF
  $iface_name:
    dhcp4: false
    dhcp6: false
    accept-ra: false
    link-local: [ ipv6 ]
EOF
    done

    # Create cloud-init ISO
    local iso_path=$(get_vdc_cloud_init_iso "$dc_name" "$full_vm_name")
    
    if command -v genisoimage >/dev/null 2>&1; then
        genisoimage -output "$iso_path" \
            -volid cidata \
            -joliet -rock \
            "$cloud_init_dir/user-data" \
            "$cloud_init_dir/meta-data" \
            "$cloud_init_dir/network-config" \
            >/dev/null 2>&1
    elif command -v mkisofs >/dev/null 2>&1; then
        mkisofs -output "$iso_path" \
            -volid cidata \
            -joliet -rock \
            "$cloud_init_dir/user-data" \
            "$cloud_init_dir/meta-data" \
            "$cloud_init_dir/network-config" \
            >/dev/null 2>&1
    else
        log_error "Neither genisoimage nor mkisofs found. Please install cloud-image-utils."
        exit 1
    fi
    
    log_success "✓ Cloud-init configuration created for $full_vm_name"
}

create_sonic_disk() {
    local config_file="$1"
    local sw_name="$2"

    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")

    local disk_dir=$(get_vdc_disks_dir "$dc_name")
    mkdir -p "$disk_dir"

    local base_image="$PROJECT_ROOT/images/ubuntu-24.04-server-cloudimg-amd64.img"
    local disk_path=$(get_vdc_disk_path "$dc_name" "$sw_name")

    log_info "Creating disk for FRR switch $sw_name from Ubuntu 24.04 base image..."
    
    # Check if base image exists
    if [[ ! -f "$base_image" ]]; then
        log_error "Ubuntu 24.04 base image not found: $base_image"
        log_error "Please run: ./scripts/deploy-virtual-dc.sh --check-prereqs"
        exit 1
    fi
    
    # Create a copy of the base image for this switch
    qemu-img create -f qcow2 -F qcow2 -b "$base_image" "$disk_path" 50G
    
    log_success "✓ Disk created: $disk_path (50GB)"
}

create_sonic_vm() {
    local config_file="$1"
    local tier="$2"
    local index="$3"
    local vm_name="$4"
    local hostname="$5"
    local cpu="$6"
    local memory="$7"
    local iface_count="$8"

    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local mgmt_network="${dc_name}-mgmt"
    local disk_path=$(get_vdc_disk_path "$dc_name" "$vm_name")
    local cidata_path=$(get_vdc_cloud_init_iso "$dc_name" "$vm_name")

    log_info "Creating VM: $vm_name with Ubuntu 24.04 (Noble Numbat)"
    log_info "  vCPUs: $cpu, Memory: ${memory}MB"
    log_info "  Management network: $mgmt_network"
    log_info "  Data interfaces: $iface_count"

    # Verify disk and cloud-init exist
    if [[ ! -f "$disk_path" ]]; then
        log_error "VM disk not found: $disk_path"
        return 1
    fi

    if [[ ! -f "$cidata_path" ]]; then
        log_error "Cloud-init ISO not found: $cidata_path"
        return 1
    fi

    # Build virt-install command with Ubuntu 24.04 settings
    # Add management interface (enp1s0) + placeholder data interfaces (enp2s0, enp3s0, etc.)
    # Data interfaces are initially connected to isolated networks
    # The cabling module will update them to connect to correct P2P networks
    local cmd="virt-install \
        --name $vm_name \
        --vcpus $cpu \
        --memory $memory \
        --disk path=$disk_path,format=qcow2,bus=virtio \
        --disk path=$cidata_path,device=cdrom,readonly=on \
        --network network=$mgmt_network,model=virtio \
        --os-variant ubuntu24.04 \
        --graphics none \
        --console pty,target_type=serial \
        --boot hd,cdrom \
        --import \
        --noautoconsole"
    
    # Add data plane interfaces in sequential order
    # This ensures enp2s0, enp3s0, enp4s0, etc. are in correct PCI slots
    for i in $(seq 1 $iface_count); do
        # Initially connect to default network (will be updated by cabling module)
        cmd="$cmd --network network=default,model=virtio"
    done

    log_info "Executing: virt-install for $vm_name..."
    log_info "  Creating with $iface_count data interfaces (enp2s0-enp$((iface_count+1))s0)"
    log_info "  Cabling module will connect them to P2P networks"

    # Execute virt-install
    if eval "$cmd"; then
        log_success "✓ VM $vm_name created and started successfully"
        log_info "  Booting Ubuntu 24.04 with cloud-init..."
        log_info "  VM will reboot once after cloud-init completes"
        return 0
    else
        log_error "Failed to create VM $vm_name"
        return 1
    fi
}

wait_for_switch_ready() {
    local config_file="$1"
    local sw_name="$2"
    local mgmt_ip="$3"
    
    local mgmt_ip_addr=$(echo "$mgmt_ip" | cut -d'/' -f1)
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local ssh_key_path="$PROJECT_ROOT/config/${dc_name}-ssh-key"
    
    log_info "Waiting for switch $sw_name to be accessible..."
    log_info "This may take 2-5 minutes for cloud-init to complete..."
    
    local max_attempts=60
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if ssh -i "$ssh_key_path" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 \
            -o BatchMode=yes \
            ubuntu@"$mgmt_ip_addr" "echo ready" >/dev/null 2>&1; then
            log_success "✓ Switch $sw_name is accessible via SSH"
            return 0
        fi
        
        attempt=$((attempt + 1))
        if [[ $((attempt % 10)) -eq 0 ]]; then
            log_info "Still waiting... ($attempt/$max_attempts)"
        fi
        sleep 5
    done
    
    log_warn "Switch $sw_name did not become accessible within timeout"
    log_warn "It may still be initializing. Check with: virsh console $sw_name"
    return 1
}

list_switches() {
    log_info "Listing all switch VMs..."
    virsh list --all | grep -E "leaf|spine|superspine" || echo "No switches found"
}

get_switch_status() {
    local sw_name="$1"

    log_info "Status for switch: $sw_name"

    # VM status
    if virsh list --all --name | grep -q "^${sw_name}$"; then
        local state=$(virsh domstate "$sw_name")
        echo "  VM State: $state"

        if [[ "$state" == "running" ]]; then
            echo "  FRR switch is running"
            # Could add SSH check for FRR status if needed
        fi
    else
        echo "  VM not found"
    fi
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
    
    # Clean up cloud-init files using vdc-paths
    # Extract DC name from switch name (e.g., prod-leaf1 -> prod)
    local dc_name=$(echo "$sw_name" | sed -E 's/^([^-]+)-.*/\1/')
    remove_vdc_cloud_init_iso "$dc_name" "$sw_name"
}
