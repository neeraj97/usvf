#!/bin/bash
################################################################################
# Hypervisor Deployment Module
#
# Deploys and configures hypervisor VMs with:
# - KVM virtual machines
# - FRRouting for BGP
# - Multiple network interfaces (management + data)
# - Cloud-init for initial configuration
################################################################################

deploy_hypervisors() {
    local config_file="$1"
    local dry_run="${2:-false}"
    
    log_info "Deploying hypervisor VMs..."
    
    local hv_count=$(yq eval '.hypervisors | length' "$config_file")
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    
    log_info "Number of hypervisors to deploy: $hv_count"
    
    # Create SSH keys if they don't exist
    setup_ssh_keys "$dc_name"
    
    # Deploy each hypervisor
    for i in $(seq 0 $((hv_count - 1))); do
        deploy_single_hypervisor "$config_file" "$i" "$dry_run"
    done
    
    log_success "All hypervisors deployed successfully"
}

deploy_single_hypervisor() {
    local config_file="$1"
    local index="$2"
    local dry_run="$3"
    
    # Extract hypervisor configuration
    local hv_name=$(yq eval ".hypervisors[$index].name" "$config_file")
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local short_name=$(yq eval ".hypervisors[$index].short_name" "$config_file")
    local router_id=$(yq eval ".hypervisors[$index].router_id" "$config_file")
    local asn=$(yq eval ".hypervisors[$index].asn" "$config_file")
    local mgmt_ip=$(yq eval ".hypervisors[$index].management.ip" "$config_file")
    local cpu=$(yq eval ".hypervisors[$index].resources.cpu" "$config_file")
    local memory=$(yq eval ".hypervisors[$index].resources.memory" "$config_file")
    local disk=$(yq eval ".hypervisors[$index].resources.disk" "$config_file")
    
    # Create full VM name with DC prefix for proper isolation
    local full_vm_name="${dc_name}-${hv_name}"
    
    # Get number of data interfaces
    local iface_count=$(yq eval ".hypervisors[$index].data_interfaces | length" "$config_file")
    
    log_info "Deploying hypervisor: $full_vm_name"
    log_info "  Hostname: $hv_name"
    log_info "  Router ID: $router_id, ASN: $asn"
    log_info "  Management IP: $mgmt_ip"
    log_info "  Resources: CPU=$cpu, Memory=${memory}MB, Disk=${disk}GB"
    log_info "  Data Interfaces: $iface_count"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would create VM: $full_vm_name"
        return 0
    fi
    
    # Create cloud-init configuration (use original hv_name for hostname)
    create_hypervisor_cloud_init "$config_file" "$index" "$hv_name" "$full_vm_name"

    # Create VM disk (use full_vm_name for disk file) and additional disks
    create_hypervisor_disk "$config_file" "$full_vm_name" "$disk" "$index"

    # Create and start VM (use full_vm_name for VM name)
    create_hypervisor_vm "$config_file" "$index" "$full_vm_name" "$hv_name" "$cpu" "$memory" "$iface_count"
    
    log_success "✓ Hypervisor $full_vm_name deployed"
}

setup_ssh_keys() {
    local dc_name="$1"
    local ssh_key_path=$(get_vdc_ssh_private_key "$dc_name")
    
    if [[ ! -f "$ssh_key_path" ]]; then
        # Ensure SSH keys directory exists
        local ssh_keys_dir=$(get_vdc_ssh_keys_dir "$dc_name")
        mkdir -p "$ssh_keys_dir"
        
        log_info "Generating SSH key pair for VM access..."
        ssh-keygen -t rsa -b 4096 -f "$ssh_key_path" -N "" -C "virtual-dc-${dc_name}"
        log_success "✓ SSH keys generated: $ssh_key_path"
    else
        log_info "Using existing SSH keys: $ssh_key_path"
    fi
}

create_hypervisor_cloud_init() {
    local config_file="$1"
    local index="$2"
    local hv_name="$3"
    local full_vm_name="$4"

    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local ssh_key_path=$(get_vdc_ssh_public_key "$dc_name")
    local ssh_pubkey=$(cat "$ssh_key_path")

    local router_id=$(yq eval ".hypervisors[$index].router_id" "$config_file")
    local asn=$(yq eval ".hypervisors[$index].asn" "$config_file")
    local mgmt_ip=$(yq eval ".hypervisors[$index].management.ip" "$config_file")

    # Get number of data interfaces for BGP neighbor configuration
    local iface_count=$(yq eval ".hypervisors[$index].data_interfaces | length" "$config_file")

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
    
    # Create meta-data
    cat > "$cloud_init_dir/meta-data" <<EOF
instance-id: $hv_name
local-hostname: $hv_name
EOF
    
    # Create user-data
    cat > "$cloud_init_dir/user-data" <<EOF
#cloud-config
hostname: $hv_name
fqdn: ${hv_name}.virtual-dc.local
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
  - jq
  - iperf3
  - mtr
  - traceroute
  - ethtool

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
      ! FRRouting configuration for $hv_name
      ! Ubuntu 24.04 Noble Numbat
      ! Generated by Virtual DC Deployment Tool
      !
      frr version 10.0
      frr defaults traditional
      hostname $hv_name
      log syslog informational
      service integrated-vtysh-config
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
        neighbor FABRIC route-map ALLOW-ALL in
        neighbor FABRIC route-map ALLOW-ALL out
        ! Redistribute connected routes from lo1 interface only
        redistribute connected route-map REDISTRIBUTE-LO1
        maximum-paths 64
        maximum-paths ibgp 64
       exit-address-family
       !
       address-family l2vpn evpn
        neighbor FABRIC activate
       exit-address-family
      !
      ! Route maps
      ! Allow all routes from BGP neighbors
      route-map ALLOW-ALL permit 10
        set src $router_id
      !
      ip protocol bgp route-map ALLOW-ALL
      ! Redistribute only connected routes from lo1 interface
      route-map REDISTRIBUTE-LO1 permit 10
       match interface lo1
      !
      end
    permissions: '0640'

  - path: /etc/sysctl.d/99-forwarding.conf
    content: |
      net.ipv4.ip_forward=1
      net.ipv6.conf.all.forwarding=1
    permissions: '0644'

runcmd:
  - echo "Starting cloud-init setup for $hv_name..."
  - sysctl -p /etc/sysctl.d/99-forwarding.conf
  - sleep 2
  - echo "Verifying lo1 interface..."
  - ip addr show lo1
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
  - sleep 2
  - systemctl enable frr
  - systemctl restart frr
  - sleep 3
  - systemctl status frr --no-pager
  - |
    cat > /etc/motd <<MOTD
    ============================================================
    Ubuntu 24.04 LTS (Noble Numbat) - Hypervisor Node
    ============================================================
    Hostname:   $hv_name
    Router ID:  $router_id (on lo1)
    BGP ASN:    $asn
    Role:       Virtual DC Hypervisor with BGP routing
    
    FRRouting:  Enabled (BGP Unnumbered)
    Redistribution: Kernel routes from lo1 only
    
    Quick Commands:
      - vtysh               # Enter FRR CLI
      - show ip bgp summary # Check BGP status
      - show ip route       # View routing table
      - ip addr show lo1    # View lo1 interface
    ============================================================
    MOTD
  - echo "Cloud-init completed for $hv_name" | systemd-cat -t cloud-init

power_state:
  mode: reboot
  timeout: 30
  condition: True
EOF
    
    # Create network-config
    # Configure management interface (enp1s0), data interfaces (enp2s0, enp3s0, etc.), and lo1
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

    # Add lo1 dummy interface for BGP router ID (persistent across reboots)
    cat >> "$cloud_init_dir/network-config" <<EOF
dummy-devices:
  lo1:
    addresses:
      - $router_id/32
  dum-ex:
    
EOF
    
    # Create cloud-init ISO
    local iso_path=$(get_vdc_cloud_init_iso "$dc_name" "$full_vm_name")
    
    if command -v genisoimage &> /dev/null; then
        genisoimage -output "$iso_path" \
            -volid cidata -joliet -rock \
            "$cloud_init_dir/user-data" \
            "$cloud_init_dir/meta-data" \
            "$cloud_init_dir/network-config"
    elif command -v mkisofs &> /dev/null; then
        mkisofs -output "$iso_path" \
            -volid cidata -joliet -rock \
            "$cloud_init_dir/user-data" \
            "$cloud_init_dir/meta-data" \
            "$cloud_init_dir/network-config"
    else
        log_error "Neither genisoimage nor mkisofs found. Cannot create cloud-init ISO."
        return 1
    fi
    
    log_success "✓ Cloud-init configuration created for $full_vm_name"
}

create_hypervisor_disk() {
    local config_file="$1"
    local vm_name="$2"
    local disk_size="$3"
    local index="$4"  # Hypervisor index for additional disks lookup

    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")

    local disk_dir=$(get_vdc_disks_dir "$dc_name")
    mkdir -p "$disk_dir"

    local disk_path=$(get_vdc_disk_path "$dc_name" "$vm_name")
    local base_image="$PROJECT_ROOT/images/ubuntu-24.04-server-cloudimg-amd64.img"

    log_info "Creating disk for $vm_name (${disk_size}GB)..."

    # Check if base image exists
    if [[ ! -f "$base_image" ]]; then
        log_error "Ubuntu 24.04 base image not found: $base_image"
        log_error "Run: ./deploy-virtual-dc.sh --check-prereqs to download it"
        return 1
    fi

    # Create a copy-on-write disk based on Ubuntu 24.04 cloud image
    log_info "Using Ubuntu 24.04 Noble Numbat cloud image as base"
    qemu-img create -f qcow2 -F qcow2 -b "$base_image" "$disk_path" "${disk_size}G"

    if [[ $? -eq 0 ]]; then
        log_success "✓ VM disk created: $disk_path (${disk_size}GB, based on Ubuntu 24.04)"

        # Show disk info
        local disk_info=$(qemu-img info "$disk_path" | grep "virtual size")
        log_info "  $disk_info"
    else
        log_error "Failed to create VM disk"
        return 1
    fi

    # Create additional disks if configured
    if [[ -n "$index" ]]; then
        create_additional_disks "$config_file" "$vm_name" "$index"
    fi
}

create_additional_disks() {
    local config_file="$1"
    local vm_name="$2"
    local index="$3"

    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local disk_dir=$(get_vdc_disks_dir "$dc_name")

    # Check if additional_disks is defined
    local additional_disk_count=$(yq eval ".hypervisors[$index].additional_disks | length" "$config_file" 2>/dev/null || echo "0")

    if [[ "$additional_disk_count" == "0" || "$additional_disk_count" == "null" ]]; then
        log_info "No additional disks configured for $vm_name"
        return 0
    fi

    log_info "Creating $additional_disk_count additional disk(s) for $vm_name..."

    for i in $(seq 0 $((additional_disk_count - 1))); do
        local disk_name=$(yq eval ".hypervisors[$index].additional_disks[$i].name" "$config_file")
        local disk_size=$(yq eval ".hypervisors[$index].additional_disks[$i].size" "$config_file")
        local disk_format=$(yq eval ".hypervisors[$index].additional_disks[$i].format // \"qcow2\"" "$config_file")

        # Validate values
        [[ "$disk_name" == "null" || -z "$disk_name" ]] && disk_name="data$((i+1))"
        [[ "$disk_size" == "null" || -z "$disk_size" ]] && disk_size="10"
        [[ "$disk_format" == "null" || -z "$disk_format" ]] && disk_format="qcow2"

        local additional_disk_path="${disk_dir}/${vm_name}-${disk_name}.${disk_format}"

        log_info "  Creating additional disk: ${disk_name} (${disk_size}GB, ${disk_format})"

        # Create empty disk (not based on any image)
        if [[ "$disk_format" == "raw" ]]; then
            qemu-img create -f raw "$additional_disk_path" "${disk_size}G"
        else
            qemu-img create -f qcow2 "$additional_disk_path" "${disk_size}G"
        fi

        if [[ $? -eq 0 ]]; then
            log_success "  ✓ Additional disk created: $additional_disk_path"
        else
            log_error "  Failed to create additional disk: $disk_name"
            return 1
        fi
    done

    log_success "✓ All additional disks created for $vm_name"
}

create_hypervisor_vm() {
    local config_file="$1"
    local index="$2"
    local vm_name="$3"
    local hostname="$4"
    local cpu="$5"
    local memory="$6"
    local iface_count="$7"

    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local mgmt_network="${dc_name}-mgmt"
    local disk_path=$(get_vdc_disk_path "$dc_name" "$vm_name")
    local cidata_path=$(get_vdc_cloud_init_iso "$dc_name" "$vm_name")
    local disk_dir=$(get_vdc_disks_dir "$dc_name")

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
    # Add management interface (enp1s0) + data interfaces connected to correct P2P networks
    # P2P networks are pre-created, so we can connect directly
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

    # Add additional disks if configured
    local additional_disk_count=$(yq eval ".hypervisors[$index].additional_disks | length" "$config_file" 2>/dev/null || echo "0")
    if [[ "$additional_disk_count" != "0" && "$additional_disk_count" != "null" ]]; then
        log_info "  Additional disks: $additional_disk_count"

        for i in $(seq 0 $((additional_disk_count - 1))); do
            local disk_name=$(yq eval ".hypervisors[$index].additional_disks[$i].name" "$config_file")
            local disk_format=$(yq eval ".hypervisors[$index].additional_disks[$i].format // \"qcow2\"" "$config_file")

            [[ "$disk_name" == "null" || -z "$disk_name" ]] && disk_name="data$((i+1))"
            [[ "$disk_format" == "null" || -z "$disk_format" ]] && disk_format="qcow2"

            local additional_disk_path="${disk_dir}/${vm_name}-${disk_name}.${disk_format}"

            if [[ -f "$additional_disk_path" ]]; then
                log_info "    Attaching disk: ${disk_name} (${disk_format})"
                cmd="$cmd --disk path=$additional_disk_path,format=$disk_format,bus=virtio"
            else
                log_warn "    Additional disk not found: $additional_disk_path"
            fi
        done
    fi

    # Add data plane interfaces in sequential order, connected to correct P2P networks
    # This ensures enp2s0, enp3s0, enp4s0, etc. are in correct PCI slots
    for i in $(seq 0 $((iface_count - 1))); do
        local iface_name=$(yq eval ".hypervisors[$index].data_interfaces[$i].name" "$config_file")
        local p2p_network=$(lookup_interface_network "$config_file" "$hostname" "$iface_name")

        if [[ "$p2p_network" == "none" ]]; then
            log_warn "No P2P network found for $hostname:$iface_name, skipping interface"
            continue
        fi

        log_info "  $iface_name → $p2p_network"
        cmd="$cmd --network network=$p2p_network,model=virtio"
    done

    log_info "Executing: virt-install for $vm_name..."
    log_info "  Creating with $iface_count data interfaces directly connected to P2P networks"

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

list_hypervisors() {
    log_info "Listing all hypervisor VMs..."
    virsh list --all
}

delete_hypervisor() {
    local vm_name="$1"
    
    log_info "Deleting hypervisor: $vm_name"
    
    # Stop VM if running
    if virsh list --name | grep -q "^${vm_name}$"; then
        virsh destroy "$vm_name"
    fi
    
    # Undefine VM
    if virsh list --all --name | grep -q "^${vm_name}$"; then
        virsh undefine "$vm_name" --remove-all-storage
        log_success "✓ Hypervisor $vm_name deleted"
    else
        log_warn "Hypervisor $vm_name not found"
    fi
}

get_hypervisor_ip() {
    local vm_name="$1"
    
    # Get IP from virsh
    local ip=$(virsh domifaddr "$vm_name" | grep -oP '(\d+\.){3}\d+' | head -n1)
    
    if [[ -n "$ip" ]]; then
        echo "$ip"
    else
        log_error "Could not determine IP for $vm_name"
        return 1
    fi
}
