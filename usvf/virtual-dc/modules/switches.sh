#!/bin/bash
################################################################################
# SONiC Switch Deployment Module
#
# Deploys and configures SONiC switch VMs with:
# - Ubuntu 24.04 VMs as switch hosts
# - Docker with SONiC-VS containers
# - BGP configuration via SONiC CLI
# - Multiple network interfaces
# - Management interface configuration
#
# Method: SONiC-VS running in Docker containers on Ubuntu VMs
################################################################################

deploy_switches() {
    local config_file="$1"
    local dry_run="${2:-false}"
    
    log_info "=========================================="
    log_info "DEPLOYING SONiC SWITCHES"
    log_info "=========================================="
    log_info "Method: Ubuntu 24.04 VMs + SONiC-VS Docker Containers"
    log_info "Image: netreplica/docker-sonic-vs:latest"
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
    
    log_success "✓ All SONiC switch VMs deployed successfully"
    log_info "Note: SONiC-VS containers will start automatically after VMs boot"
    log_info "Access switches via: ssh ubuntu@<switch-mgmt-ip>"
    log_info "Access SONiC CLI: docker exec -it sonic-vs bash"
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
    local ports=$(yq eval ".switches.$tier[$index].ports" "$config_file")
    local port_speed=$(yq eval ".switches.$tier[$index].port_speed" "$config_file")
    
    # Create full VM name with DC prefix for proper isolation
    local full_vm_name="${dc_name}-${sw_name}"
    
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Deploying $tier switch: $full_vm_name"
    log_info "  Hostname: $sw_name"
    log_info "  Router ID: $router_id"
    log_info "  ASN: $asn"
    log_info "  Management IP: $mgmt_ip"
    log_info "  Ports: $ports @ $port_speed"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would create SONiC switch VM: $full_vm_name"
        return 0
    fi
    
    # Step 1: Create cloud-init configuration for Ubuntu VM (use original sw_name for hostname)
    create_sonic_cloud_init "$config_file" "$tier" "$index" "$sw_name" "$full_vm_name"
    
    # Step 2: Create VM disk (use full_vm_name for disk file)
    create_sonic_disk "$config_file" "$full_vm_name"
    
    # Step 3: Create and start Ubuntu VM that will run SONiC-VS (use full_vm_name for VM name)
    create_sonic_vm "$config_file" "$full_vm_name" "$sw_name" "$ports"
    
    log_success "✓ SONiC switch VM $full_vm_name deployed (SONiC-VS will auto-start)"
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
    local ports=$(yq eval ".switches.$tier[$index].ports" "$config_file")

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

    log_info "Creating cloud-init configuration for $full_vm_name..."

    # Get list of SONiC interfaces connected to this switch from cabling
    local connected_sonic_interfaces=$(yq eval ".cabling[] | select(.destination.device == \"$sw_name\") | .destination.interface" "$config_file")

    # Map SONiC interface names to virtio interface names
    # Ethernet1 -> enp2s0 (2nd interface after management enp1s0)
    # Ethernet2 -> enp3s0, etc.
    local connected_host_interfaces=""
    local iface_num=2
    for sonic_iface in $connected_sonic_interfaces; do
        connected_host_interfaces="$connected_host_interfaces enp${iface_num}s0"
        iface_num=$((iface_num + 1))
    done
    connected_host_interfaces=$(echo $connected_host_interfaces | xargs)  # trim whitespace

    # Note: We don't create a static SONiC config file
    # BGP configuration is done dynamically via vtysh in start-sonic.sh
    # This allows auto-detection of interfaces at runtime


    # Create startup script with veth/bridge approach (FRR runs in SONiC container)
    cat > "$cloud_init_dir/start-sonic.sh" <<EOFSCRIPT
#!/bin/bash
set -e

echo "Starting SONiC-VS container deployment for switch: $sw_name..."

# Wait for Docker to be ready
for i in {1..30}; do
    if docker ps >/dev/null 2>&1; then
        echo "Docker is ready"
        break
    fi
    echo "Waiting for Docker... (\$i/30)"
    sleep 2
done

# Get list of data plane interfaces (excluding management enp1s0)
DATA_IFACES=\$(ls /sys/class/net/ | grep ^enp | grep -v enp1s0 | sort)
echo "Data plane interfaces detected: \$DATA_IFACES"

# Bring up all data plane interfaces
echo "Bringing up data plane interfaces..."
for iface in \$DATA_IFACES; do
    echo "  Configuring \$iface"
    ip link set \$iface up
    ip link set \$iface promisc on
    sysctl -w net.ipv6.conf.\${iface}.disable_ipv6=0
    sysctl -w net.ipv6.conf.\${iface}.autoconf=1
done

# Pull SONiC-VS image
echo "Pulling SONiC-VS Docker image..."
docker pull netreplica/docker-sonic-vs:latest

# Stop and remove any existing sonic-vs container
docker stop sonic-vs 2>/dev/null || true
docker rm sonic-vs 2>/dev/null || true

# Start SONiC-VS container with network=none (we'll add interfaces manually)
echo "Starting SONiC-VS container..."
docker run -d \\
    --name sonic-vs \\
    --privileged \\
    --network none \\
    --hostname $sw_name \\
    netreplica/docker-sonic-vs:latest

# Wait for container to start
sleep 5

# Check if container is running
if ! docker ps | grep -q sonic-vs; then
    echo "✗ Failed to start SONiC-VS container"
    exit 1
fi

echo "✓ SONiC-VS container started"

# Get container PID and create network namespace symlink
SONIC_PID=\$(docker inspect -f '{{.State.Pid}}' sonic-vs)
SONIC_NETNS="sonic-netns"
mkdir -p /var/run/netns
ln -sf /proc/\$SONIC_PID/ns/net /var/run/netns/\$SONIC_NETNS

echo "Connecting host interfaces to SONiC container using veth pairs and bridges..."

# Create veth pairs and bridges for each host interface
ETH_NUM=1
for HOST_IFACE in \$DATA_IFACES; do
    VETH_HOST="veth-h\${ETH_NUM}"
    VETH_SONIC="eth\${ETH_NUM}"
    BR_NAME="br-\${HOST_IFACE}"

    echo "  Connecting \$HOST_IFACE -> eth\${ETH_NUM} in SONiC"

    # Create veth pair
    ip link add \$VETH_HOST type veth peer name \$VETH_SONIC

    # Move SONiC end to container namespace
    ip link set \$VETH_SONIC netns \$SONIC_NETNS

    # Create bridge and connect physical interface and veth
    ip link add name \$BR_NAME type bridge
    ip link set \$BR_NAME up
    ip link set \$HOST_IFACE master \$BR_NAME
    ip link set \$VETH_HOST master \$BR_NAME
    ip link set \$VETH_HOST up

    # Configure SONiC end inside container
    ip netns exec \$SONIC_NETNS ip link set \$VETH_SONIC up
    ip netns exec \$SONIC_NETNS ip link set \$VETH_SONIC promisc on

    ETH_NUM=\$((ETH_NUM + 1))
done

echo "✓ All interfaces connected to SONiC container"

# Wait for SONiC services to initialize
echo "Waiting for SONiC services to initialize (30 seconds)..."
sleep 30

# Configure BGP in SONiC using vtysh (FRR runs inside SONiC)
echo "Configuring BGP in SONiC container..."

# First, configure loopback interface
docker exec sonic-vs bash -c "ip addr add $router_id/32 dev lo"

# Configure BGP using vtysh
docker exec sonic-vs vtysh -c "configure terminal" \\
    -c "router bgp $asn" \\
    -c " bgp router-id $router_id" \\
    -c " bgp log-neighbor-changes" \\
    -c " no bgp default ipv4-unicast" \\
    -c " no bgp ebgp-requires-policy" \\
    -c " neighbor FABRIC peer-group" \\
    -c " neighbor FABRIC remote-as external" \\
    -c " neighbor FABRIC capability extended-nexthop"

# Add BGP neighbors for each interface
ETH_NUM=1
for HOST_IFACE in \$DATA_IFACES; do
    ETH_IFACE="eth\${ETH_NUM}"
    echo "  Adding BGP neighbor on \$ETH_IFACE"

    docker exec sonic-vs vtysh -c "configure terminal" \\
        -c "router bgp $asn" \\
        -c " neighbor \$ETH_IFACE interface peer-group FABRIC"

    ETH_NUM=\$((ETH_NUM + 1))
done

# Enable BGP for IPv4 address family
docker exec sonic-vs vtysh -c "configure terminal" \\
    -c "router bgp $asn" \\
    -c " address-family ipv4 unicast" \\
    -c "  neighbor FABRIC activate" \\
    -c "  maximum-paths 64" \\
    -c " exit-address-family" \\
    -c "exit" \\
    -c "write memory"

echo ""
echo "✓ SONiC switch is ready! BGP is running inside SONiC container."
echo ""
echo "Useful commands:"
echo "  Access SONiC: docker exec -it sonic-vs bash"
echo "  Check BGP: docker exec sonic-vs vtysh -c 'show bgp summary'"
echo "  Check interfaces: docker exec sonic-vs ip link show"
echo "  Check routes: docker exec sonic-vs vtysh -c 'show ip route'"
echo ""
docker ps | grep sonic-vs
EOFSCRIPT

    chmod +x "$cloud_init_dir/start-sonic.sh"
    
    # Create user-data for cloud-init
    cat > "$cloud_init_dir/user-data" <<EOF
#cloud-config
hostname: $sw_name
fqdn: ${sw_name}.local
manage_etc_hosts: true

users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, docker
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - $ssh_pubkey

# Set password for ubuntu user (password: ubuntu)
chpasswd:
  list: |
    ubuntu:ubuntu
  expire: false

packages:
  - docker.io
  - net-tools
  - iproute2
  - iputils-ping
  - traceroute
  - tcpdump
  - vim
  - jq
  - curl
  - bridge-utils

write_files:
  - path: /tmp/start-sonic.sh
    permissions: '0755'
    encoding: b64
    content: $(base64 -w 0 "$cloud_init_dir/start-sonic.sh")

runcmd:
  # Move files to ubuntu home directory (user exists now)
  - mkdir -p /home/ubuntu
  - mv /tmp/start-sonic.sh /home/ubuntu/start-sonic.sh
  - chown ubuntu:ubuntu /home/ubuntu/start-sonic.sh

  # Enable IPv6 and IP forwarding (needed for SONiC)
  - sysctl -w net.ipv6.conf.all.forwarding=1
  - sysctl -w net.ipv4.ip_forward=1
  - sysctl -w net.ipv6.conf.all.disable_ipv6=0
  - sysctl -w net.ipv6.conf.default.disable_ipv6=0

  # Enable and start Docker
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker ubuntu

  # Wait for Docker to be fully ready
  - sleep 5

  # Create systemd service file for SONiC-VS
  - |
    cat > /etc/systemd/system/sonic-vs.service <<'EOFSVC'
    [Unit]
    Description=SONiC Virtual Switch Container
    After=docker.service
    Requires=docker.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    User=ubuntu
    ExecStart=/home/ubuntu/start-sonic.sh
    ExecStop=/usr/bin/docker stop sonic-vs
    ExecStop=/usr/bin/docker rm sonic-vs

    [Install]
    WantedBy=multi-user.target
    EOFSVC

  # Enable SONiC-VS service (will auto-start on boot)
  - systemctl daemon-reload
  - systemctl enable sonic-vs.service
  - systemctl start sonic-vs.service
  
  # Create helpful aliases
  - echo "alias sonic='docker exec -it sonic-vs bash'" >> /home/ubuntu/.bashrc
  - echo "alias sonic-cli='docker exec -it sonic-vs sonic-cli'" >> /home/ubuntu/.bashrc
  - echo "alias sonic-logs='docker logs sonic-vs'" >> /home/ubuntu/.bashrc
  
  # Create welcome message
  - |
    cat > /etc/motd <<'EOFMOTD'
    ╔════════════════════════════════════════════════════════════╗
    ║              SONiC Virtual Switch Node                     ║
    ║                                                            ║
    ║  Switch Name: $sw_name                                
    ║  Router ID:   $router_id                                   
    ║  ASN:         $asn                                         
    ║                                                            ║
    ║  Quick Commands:                                           ║
    ║    sonic          - Enter SONiC container                  ║
    ║    sonic-cli      - Run SONiC CLI commands                 ║
    ║    sonic-logs     - View SONiC container logs              ║
    ║                                                            ║
    ║  Examples:                                                 ║
    ║    sonic                                                   ║
    ║    docker exec -it sonic-vs show ip bgp summary            ║
    ║    docker exec -it sonic-vs show interface status          ║
    ╚════════════════════════════════════════════════════════════╝
    EOFMOTD

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
    
    log_info "Creating disk for switch $sw_name from Ubuntu 24.04 base image..."
    
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
    local sw_name="$2"
    local hostname="$3"
    local ports="$4"
    
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local mgmt_network="${dc_name}-mgmt"
    local disk_path=$(get_vdc_disk_path "$dc_name" "$sw_name")
    local cloud_init_iso=$(get_vdc_cloud_init_iso "$dc_name" "$sw_name")
    
    log_info "Creating Ubuntu VM for switch: $sw_name"
    
    # Build virt-install command
    local cmd="virt-install \
        --name $sw_name \
        --vcpus 4 \
        --memory 8192 \
        --disk path=$disk_path,format=qcow2,bus=virtio \
        --disk path=$cloud_init_iso,device=cdrom \
        --network network=$mgmt_network,model=virtio \
        --os-variant ubuntu24.04 \
        --graphics none \
        --console pty,target_type=serial \
        --import \
        --noautoconsole"
    
    # Add data plane interfaces based on port count
    # Each virtio interface can represent multiple SONiC ports
    local num_data_interfaces=$((ports / 32 + 1))
    if [[ $num_data_interfaces -lt 2 ]]; then
        num_data_interfaces=2
    fi
    
    for i in $(seq 1 $num_data_interfaces); do
        cmd="$cmd --network network=default,model=virtio"
    done
    
    log_info "VM will have $num_data_interfaces data plane interfaces"
    
    # Execute virt-install
    eval "$cmd"
    
    if [[ $? -eq 0 ]]; then
        log_success "✓ VM $sw_name created and started"
        log_info "VM will reboot after cloud-init completes SONiC-VS installation"
    else
        log_error "Failed to create VM $sw_name"
        exit 1
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

configure_sonic_switch() {
    local config_file="$1"
    local sw_name="$2"
    local tier="$3"
    local index="$4"
    
    local mgmt_ip=$(yq eval ".switches.$tier[$index].management.ip" "$config_file")
    local mgmt_ip_addr=$(echo "$mgmt_ip" | cut -d'/' -f1)
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local ssh_key_path="$PROJECT_ROOT/config/${dc_name}-ssh-key"
    
    log_info "Configuring SONiC on switch $sw_name..."
    
    # Wait for SONiC container to be running
    local max_wait=30
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        if ssh -i "$ssh_key_path" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            ubuntu@"$mgmt_ip_addr" "docker ps | grep sonic-vs" >/dev/null 2>&1; then
            log_success "✓ SONiC-VS container is running on $sw_name"
            break
        fi
        waited=$((waited + 1))
        sleep 2
    done
    
    # Apply initial SONiC configuration
    ssh -i "$ssh_key_path" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        ubuntu@"$mgmt_ip_addr" <<'EOFREMOTE'
# Load configuration into SONiC
docker exec sonic-vs config load /etc/sonic/config_db.json -y

# Verify SONiC is running
docker exec sonic-vs show system-health summary
EOFREMOTE
    
    log_success "✓ SONiC configured on $sw_name"
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
            # Try to check SONiC container status
            echo "  Checking SONiC container..."
            # This would require SSH access
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
