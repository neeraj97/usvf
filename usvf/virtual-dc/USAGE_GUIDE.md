# Virtual DC Usage Guide

Complete guide for deploying and managing virtual datacenter environments.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Designing Your Topology](#designing-your-topology)
3. [Configuration Examples](#configuration-examples)
4. [Deployment Workflows](#deployment-workflows)
5. [Management Operations](#management-operations)
6. [Troubleshooting](#troubleshooting)

## Getting Started

### First-Time Setup

1. **Install Prerequisites**

```bash
cd usvf/virtual-dc

# Check what's missing
./scripts/deploy-virtual-dc.sh --validate

# Install dependencies (Ubuntu)
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients \
    virtinst bridge-utils virt-manager iproute2 jq genisoimage

# Install yq
sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
    -O /usr/local/bin/yq
sudo chmod +x /usr/local/bin/yq
```

2. **Add User to libvirt Group**

```bash
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER
# Log out and back in for changes to take effect
```

3. **Start libvirt**

```bash
sudo systemctl start libvirtd
sudo systemctl enable libvirtd
```

## Designing Your Topology

### Planning Questions

Before designing your virtual DC, answer these questions:

1. **How many hypervisors do you need?**
   - Small: 2-4 hypervisors
   - Medium: 4-8 hypervisors
   - Large: 8+ hypervisors

2. **What topology tier?**
   - **Leaf-only**: Direct connections to hypervisors
   - **Leaf-Spine**: 2-tier architecture (most common)
   - **Leaf-Spine-SuperSpine**: 3-tier for larger deployments

3. **How many connections per hypervisor?**
   - Single-homed: 1 connection (no redundancy)
   - Dual-homed: 2 connections (standard)
   - Multi-homed: 4+ connections (high availability)

4. **What ASN scheme?**
   - Hypervisors: 65001-65999
   - Leaf switches: 65101-65199
   - Spine switches: 65201-65299
   - SuperSpine: 65301-65399

### Topology Design Patterns

#### Pattern 1: Small Lab (2 Hypervisors, 2 Leafs, 2 Spines)

```
    [Spine-1] ─────── [Spine-2]
      /    \           /    \
     /      \         /      \
[Leaf-1]  [Leaf-2] [Leaf-3] [Leaf-4]
   |         |        |         |
  HV1       HV2      HV3       HV4
```

#### Pattern 2: Medium Setup (4 Hypervisors, 2 Leafs, 2 Spines)

```
        [Spine-1] ─────── [Spine-2]
          /    \            /    \
         /      \          /      \
    [Leaf-1]  [Leaf-2]  [Leaf-1] [Leaf-2]
      / \        / \       / \       / \
    HV1 HV2    HV3 HV4   HV1 HV2   HV3 HV4
```

#### Pattern 3: Full 3-Tier (Production-like)

```
              [SuperSpine-1]
                /         \
               /           \
        [Spine-1]       [Spine-2]
          /   \            /   \
         /     \          /     \
    [Leaf-1] [Leaf-2] [Leaf-3] [Leaf-4]
      / \      / \      / \      / \
    HV1 HV2  HV3 HV4  HV5 HV6  HV7 HV8
```

## Configuration Examples

### Example 1: Minimal 2-Hypervisor Setup

```yaml
global:
  datacenter_name: "minimal-lab"
  management_network:
    subnet: "192.168.100.0/24"
    gateway: "192.168.100.1"

hypervisors:
  - name: "hypervisor-1"
    short_name: "hv1"
    router_id: "1.1.1.1"
    asn: 65001
    management:
      ip: "192.168.100.11/24"
    data_interfaces:
      - {name: "eth1", description: "To Leaf-1"}
    resources: {cpu: 2, memory: 2048, disk: 30}

  - name: "hypervisor-2"
    short_name: "hv2"
    router_id: "1.1.1.2"
    asn: 65002
    management:
      ip: "192.168.100.12/24"
    data_interfaces:
      - {name: "eth1", description: "To Leaf-1"}
    resources: {cpu: 2, memory: 2048, disk: 30}

switches:
  leaf:
    - name: "leaf-1"
      router_id: "2.2.2.1"
      asn: 65101
      management: {ip: "192.168.100.101/24", switch: "mgmt-sw"}
      ports: 32
      port_speed: "10G"

cabling:
  - source: {device: "hypervisor-1", interface: "eth1"}
    destination: {device: "leaf-1", interface: "Ethernet1"}
    link_type: "p2p"
    description: "HV1 to Leaf-1"

  - source: {device: "hypervisor-2", interface: "eth1"}
    destination: {device: "leaf-1", interface: "Ethernet2"}
    link_type: "p2p"
    description: "HV2 to Leaf-1"
```

### Example 2: Dual-Homed Hypervisors

```yaml
hypervisors:
  - name: "hypervisor-1"
    short_name: "hv1"
    router_id: "1.1.1.1"
    asn: 65001
    management:
      ip: "192.168.100.11/24"
    data_interfaces:
      - {name: "eth1", description: "To Leaf-1"}
      - {name: "eth2", description: "To Leaf-2"}
    resources: {cpu: 4, memory: 4096, disk: 50}

switches:
  leaf:
    - name: "leaf-1"
      router_id: "2.2.2.1"
      asn: 65101
    - name: "leaf-2"
      router_id: "2.2.2.2"
      asn: 65102

cabling:
  - source: {device: "hypervisor-1", interface: "eth1"}
    destination: {device: "leaf-1", interface: "Ethernet1"}
  - source: {device: "hypervisor-1", interface: "eth2"}
    destination: {device: "leaf-2", interface: "Ethernet1"}
```

## Deployment Workflows

### Workflow 1: Full Automated Deployment

```bash
# Validate configuration
./scripts/deploy-virtual-dc.sh --validate

# Deploy everything
./scripts/deploy-virtual-dc.sh --config config/topology.yaml

# Wait for deployment to complete (10-15 minutes)
# Verify deployment
./scripts/deploy-virtual-dc.sh --step verify
```

### Workflow 2: Step-by-Step Deployment

```bash
# Step 1: Validate
./scripts/deploy-virtual-dc.sh --step validate

# Step 2: Check prerequisites
./scripts/deploy-virtual-dc.sh --step prereqs

# Step 3: Create management network
./scripts/deploy-virtual-dc.sh --step network

# Step 4: Deploy hypervisors
./scripts/deploy-virtual-dc.sh --step hypervisors

# Step 5: Deploy switches
./scripts/deploy-virtual-dc.sh --step switches

# Step 6: Configure cabling
./scripts/deploy-virtual-dc.sh --step cabling

# Step 7: Configure BGP
./scripts/deploy-virtual-dc.sh --step bgp

# Step 8: Verify
./scripts/deploy-virtual-dc.sh --step verify
```

### Workflow 3: Dry Run Testing

```bash
# Preview what would be created
./scripts/deploy-virtual-dc.sh --dry-run

# Review the output
# Make adjustments to config
# Deploy for real
./scripts/deploy-virtual-dc.sh
```

## Management Operations

### Accessing VMs

```bash
# List all VMs
virsh list --all

# SSH into hypervisor
DC_NAME="virtual-dc-lab"
ssh -i config/${DC_NAME}-ssh-key ubuntu@192.168.100.11

# Access VM console
virsh console hypervisor-1
# Press Ctrl+] to exit
```

### Monitoring BGP

```bash
# Check BGP on all hypervisors
for ip in 192.168.100.{11..14}; do
    echo "=== Checking $ip ==="
    ssh -i config/virtual-dc-lab-ssh-key ubuntu@$ip \
        "sudo vtysh -c 'show bgp summary'"
done

# Check specific hypervisor
ssh -i config/virtual-dc-lab-ssh-key ubuntu@192.168.100.11 \
    "sudo vtysh -c 'show bgp ipv4 unicast'"
```

### Network Diagnostics

```bash
# Show all networks
virsh net-list --all

# Check network details
virsh net-dumpxml virtual-dc-lab-mgmt

# Show bridge interfaces
ip link show type bridge

# Check P2P links
virsh net-list --all | grep p2p
```

### VM Operations

```bash
# Start a VM
virsh start hypervisor-1

# Stop a VM
virsh shutdown hypervisor-1

# Force stop
virsh destroy hypervisor-1

# Restart
virsh reboot hypervisor-1

# Check VM info
virsh dominfo hypervisor-1

# View VM resources
virsh domstats hypervisor-1
```

### Cleanup

```bash
# Delete specific hypervisor
virsh destroy hypervisor-1
virsh undefine hypervisor-1 --remove-all-storage

# Clean up entire deployment
./scripts/cleanup-virtual-dc.sh

# Or manually
for vm in $(virsh list --all --name | grep -E 'hypervisor|leaf|spine'); do
    virsh destroy $vm 2>/dev/null
    virsh undefine $vm --remove-all-storage 2>/dev/null
done

# Remove networks
for net in $(virsh net-list --all --name | grep -E 'virtual-dc|p2p'); do
    virsh net-destroy $net 2>/dev/null
    virsh net-undefine $net 2>/dev/null
done
```

## Troubleshooting

### Issue: VMs Won't Start

**Symptom**: `virsh list` shows VMs in "shut off" state

**Solutions**:

```bash
# Check libvirt logs
sudo journalctl -u libvirtd -n 50

# Check VM definition
virsh dumpxml hypervisor-1

# Try starting with console
virsh start hypervisor-1 --console

# Check disk permissions
ls -la /var/lib/libvirt/images/
```

### Issue: Can't SSH to VMs

**Symptom**: SSH connection refused or timeout

**Solutions**:

```bash
# Check if VM is actually running
virsh list

# Check if VM has IP
virsh domifaddr hypervisor-1

# Try console access
virsh console hypervisor-1

# Check cloud-init logs
virsh console hypervisor-1
# Inside VM: sudo cat /var/log/cloud-init.log

# Verify SSH key permissions
ls -la config/*-ssh-key*
chmod 600 config/*-ssh-key
```

### Issue: BGP Sessions Not Establishing

**Symptom**: `show bgp summary` shows neighbors in Idle/Active state

**Solutions**:

```bash
# Check interface status
sudo vtysh -c "show interface brief"

# Verify neighbors configured
sudo vtysh -c "show running-config"

# Check if interfaces are up
ip link show

# Enable IPv6 on interfaces
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0
sudo sysctl -w net.ipv6.conf.eth1.disable_ipv6=0

# Restart FRR
sudo systemctl restart frr
```

### Issue: No Connectivity Between VMs

**Symptom**: Can't ping between hypervisors

**Solutions**:

```bash
# Check virtual networks
virsh net-list --all

# Verify cabling
virsh net-dumpxml p2p-link-0

# Check if interfaces attached to VMs
virsh domiflist hypervisor-1

# Restart VMs
virsh reboot hypervisor-1
```

### Debug Mode

```bash
# Enable verbose logging
export DEBUG=1
./scripts/deploy-virtual-dc.sh

# Check module output
bash -x scripts/deploy-virtual-dc.sh --step hypervisors
```

## Best Practices

1. **Start Small**: Begin with 2 hypervisors and 1 leaf, then expand
2. **Use Dry Run**: Always test with `--dry-run` first
3. **Version Control**: Keep your topology.yaml in git
4. **Document Changes**: Update topology_visual when changing cabling
5. **Regular Backups**: Backup VM disks before major changes
6. **Monitor Resources**: Check host system resources regularly
7. **Clean Up**: Remove old deployments to free resources

## Performance Tuning

### For Large Deployments

```yaml
# Reduce VM resources
hypervisors:
  - resources:
      cpu: 2          # Instead of 4
      memory: 2048    # Instead of 4096
      disk: 20        # Instead of 50
```

### Optimize libvirt

```bash
# Enable KSM (Kernel Samepage Merging)
echo 1 | sudo tee /sys/kernel/mm/ksm/run

# Adjust CPU governor
sudo cpupower frequency-set -g performance
```

## Next Steps

- Review [README.md](README.md) for detailed documentation
- Check [examples/](examples/) for more topology configurations
- Read module source code for advanced customization
- Join the community for support and contributions
