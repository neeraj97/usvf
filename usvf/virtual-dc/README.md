# Virtual Datacenter Deployment System

A comprehensive toolkit for deploying and managing virtual datacenter environments with hypervisors, SONiC switches, and BGP unnumbered routing.

## Overview

This system allows you to design and deploy a complete virtual datacenter infrastructure including:

- **Hypervisors**: KVM-based VMs running as compute nodes with FRRouting for BGP
- **SONiC Switches**: Virtual switches organized in Leaf/Spine/SuperSpine architecture
- **BGP Unnumbered**: Layer 3 fabric using BGP unnumbered for simplified configuration
- **Management Network**: Dedicated L2 network for out-of-band management
- **Visual Topology Design**: ASCII art-based topology visualization in YAML config

## Features

✅ **Flexible Topology Design** - Define any Leaf/Spine/SuperSpine topology

✅ **BGP Unnumbered** - IPv6 link-local based BGP peering

✅ **YAML Configuration** - Human-readable configuration with visual topology

✅ **Automated Deployment** - Single command to deploy entire infrastructure

✅ **Validation** - Built-in configuration validation and verification

✅ **Modular Architecture** - Extensible module-based design

✅ **KVM/QEMU Support** - Uses industry-standard virtualization

✅ **FRRouting Integration** - Full BGP routing stack on hypervisors

## Architecture

```
┌─────────────────────── VIRTUAL DATACENTER ───────────────────────┐
│                                                                   │
│                         [SuperSpine-1]                            │
│                         /            \                            │
│                        /              \                           │
│                  [Spine-1]          [Spine-2]                     │
│                   /    \              /    \                      │
│                  /      \            /      \                     │
│            [Leaf-1]   [Leaf-2]  [Leaf-3]  [Leaf-4]               │
│              / \         / \        / \       / \                 │
│             /   \       /   \      /   \     /   \                │
│           HV1  HV2    HV3  HV4   HV5  HV6  HV7  HV8              │
│            |    |      |    |     |    |    |    |                │
│            └────┴──────┴────┴─────┴────┴────┴────┘                │
│                    [Management Switch]                            │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Required Software

- **Operating System**: Linux (Ubuntu 22.04+ recommended) or macOS
- **Virtualization**: KVM/QEMU with libvirt
- **Hypervisor OS**: Ubuntu 24.04 LTS (Noble Numbat) - automatically downloaded
- **Tools**: yq, jq, virsh, virt-install, qemu-img, wget/curl
- **Network**: iproute2, bridge-utils
- **SSH**: openssh-client

### System Requirements

- **CPU**: Hardware virtualization support (Intel VT-x or AMD-V)
- **RAM**: Minimum 16GB (32GB+ recommended)
- **Disk**: 100GB+ free space
- **Network**: Internet connectivity for package downloads

### Installation

#### Ubuntu/Debian

```bash
sudo apt-get update
sudo apt-get install -y \
    qemu-kvm libvirt-daemon-system libvirt-clients \
    virtinst bridge-utils virt-manager \
    iproute2 jq wget curl \
    cloud-image-utils genisoimage whois

# Install yq
sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
    -O /usr/local/bin/yq
sudo chmod +x /usr/local/bin/yq

# Add user to libvirt group
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER

# Enable and start libvirt
sudo systemctl enable libvirtd
sudo systemctl start libvirtd
```

**Note**: The deployment script will automatically download Ubuntu 24.04 LTS (Noble Numbat) cloud images for hypervisor VMs.

#### macOS

```bash
brew install qemu libvirt virt-manager yq jq iproute2mac
brew services start libvirt
```

## Quick Start

### 1. Check Prerequisites

```bash
cd usvf/virtual-dc

# Check and install prerequisites (includes Ubuntu 24.04 image download)
./scripts/deploy-virtual-dc.sh --check-prereqs

# Or just validate configuration
./scripts/deploy-virtual-dc.sh --validate
```

The `--check-prereqs` option will:
- ✅ Verify all required tools are installed
- ✅ Check hardware virtualization support
- ✅ Download Ubuntu 24.04 LTS cloud image (~700MB)
- ✅ Validate network configuration

### 2. Review Configuration

Edit the topology configuration file:

```bash
vim config/topology.yaml
```

Key sections to customize:
- `hypervisors`: Define your compute nodes with ASN and Router IDs
- `switches`: Configure leaf/spine/superspine switches
- `cabling`: Define point-to-point connections
- `topology_visual`: Update ASCII art to match your design

### 3. Deploy Virtual DC

```bash
# Full deployment
./scripts/deploy-virtual-dc.sh

# Or step-by-step
./scripts/deploy-virtual-dc.sh --step validate
./scripts/deploy-virtual-dc.sh --step prereqs
./scripts/deploy-virtual-dc.sh --step network
./scripts/deploy-virtual-dc.sh --step hypervisors
./scripts/deploy-virtual-dc.sh --step switches
./scripts/deploy-virtual-dc.sh --step cabling
./scripts/deploy-virtual-dc.sh --step bgp
./scripts/deploy-virtual-dc.sh --step verify
```

### 4. Access Your Infrastructure

```bash
# List all VMs
virsh list --all

# SSH into hypervisor
ssh -i config/virtual-dc-lab-ssh-key ubuntu@192.168.100.11

# Check BGP status
ssh -i config/virtual-dc-lab-ssh-key ubuntu@192.168.100.11 \
    "sudo vtysh -c 'show bgp summary'"
```

## Topology Design Methods

You can design your virtual DC topology in three ways:

### 1. Graphical Designer (Recommended for Beginners)

Open the web-based graphical designer:

```bash
# Open in browser
open scripts/graphical-designer.html
# or
firefox scripts/graphical-designer.html
```

Features:
- 🎨 Drag-and-drop interface design
- 🔗 Visual connection builder
- 📋 Automatic YAML generation
- 💾 Save/load topology designs
- ✏️ Edit device properties in real-time

**Workflow:**
1. Drag hypervisors and switches to canvas
2. Click "Connect Mode" button
3. Click devices to create connections
4. Edit properties in right panel
5. Click "Generate YAML" to download configuration

### 2. Interactive CLI Builder

Use the command-line topology builder:

```bash
./scripts/topology-builder.sh --interactive
```

This guided wizard will ask you:
- Number of hypervisors and switches
- Device names and ASNs
- Interface counts
- Cabling preferences (auto-generate or manual)

Other options:
```bash
# Quick start with templates
./scripts/topology-builder.sh --quick-start

# Import ASCII topology diagram
./scripts/topology-builder.sh --ascii-import diagram.txt
```

### 3. Manual YAML Editing

Directly edit the YAML configuration file for full control:

```bash
vim config/topology.yaml
```

## Configuration Guide

### Topology YAML Structure

```yaml
global:
  datacenter_name: "your-dc-name"
  virtualization_platform: "kvm"
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
      - name: "eth1"
        description: "Connection to Leaf-1"
    resources:
      cpu: 4
      memory: 4096
      disk: 50

switches:
  leaf:
    - name: "leaf-1"
      router_id: "2.2.2.1"
      asn: 65101
      management:
        ip: "192.168.100.101/24"

cabling:
  - source:
      device: "hypervisor-1"
      interface: "eth1"
    destination:
      device: "leaf-1"
      interface: "Ethernet1"
    link_type: "p2p"
```

### BGP Unnumbered Configuration

BGP unnumbered uses IPv6 link-local addresses for peering:

- **No IP addressing needed** on data plane interfaces
- **Automatic neighbor discovery** using IPv6 RA
- **Simplified configuration** - just enable the interface
- **Extended next-hop** capability for IPv4 routes over IPv6 peering

## Usage Examples

### Deploy with Custom Configuration

```bash
./scripts/deploy-virtual-dc.sh --config examples/my-topology.yaml
```

### Dry Run (Preview Changes)

```bash
./scripts/deploy-virtual-dc.sh --dry-run
```

### Deploy Specific Components

```bash
# Deploy only hypervisors
./scripts/deploy-virtual-dc.sh --step hypervisors

# Configure only BGP
./scripts/deploy-virtual-dc.sh --step bgp
```

### Verify Deployment

```bash
# Check all VMs
virsh list --all

# Check networks
virsh net-list --all

# View verification report
cat config/verification-report.txt
```

### Manage Virtual DC Lifecycle

```bash
# List all resources
./scripts/deploy-virtual-dc.sh --list

# Stop all VMs (graceful shutdown)
./scripts/deploy-virtual-dc.sh --stop

# Start all VMs
./scripts/deploy-virtual-dc.sh --start

# Destroy everything (with confirmation prompt)
./scripts/deploy-virtual-dc.sh --destroy

# Destroy everything without confirmation
./scripts/deploy-virtual-dc.sh --destroy-force

# Destroy but keep Ubuntu 24.04 base image (saves bandwidth for next deployment)
./scripts/deploy-virtual-dc.sh --destroy --keep-base-images
```

## Resource Cleanup

### Complete Cleanup

To completely remove all Virtual DC resources:

```bash
cd usvf/virtual-dc

# Interactive cleanup (asks for confirmation)
./scripts/deploy-virtual-dc.sh --destroy
```

This will destroy:
- ✅ All hypervisor VMs
- ✅ All switch VMs  
- ✅ All virtual networks
- ✅ All VM disk images
- ✅ All cloud-init configurations
- ✅ All BGP configurations
- ✅ All verification reports
- ❓ SSH keys (asks for confirmation)

### Selective Cleanup

```bash
# Keep the base Ubuntu 24.04 image (saves ~700MB download next time)
./scripts/deploy-virtual-dc.sh --destroy --keep-base-images

# Force cleanup without prompts (use with caution!)
./scripts/deploy-virtual-dc.sh --destroy-force

# Just stop VMs without destroying them
./scripts/deploy-virtual-dc.sh --stop
```

### What Gets Destroyed

| Resource Type | Location | Action |
|--------------|----------|---------|
| VMs | libvirt domains | Stopped and undefined |
| VM Disks | `config/disks/*.qcow2` | Deleted |
| Networks | libvirt networks | Destroyed and undefined |
| Cloud-init | `config/cloud-init/*` | Deleted |
| BGP Configs | `config/bgp-configs/*` | Deleted |
| SSH Keys | `config/*-ssh-key*` | Optional (asks) |
| Base Image | `images/ubuntu-24.04-*.img` | Kept by default |

### Safety Features

1. **Confirmation Prompt**: Asks "Are you sure?" before destroying
2. **SSH Key Protection**: Separately asks before removing SSH keys
3. **Base Image Preservation**: Keeps Ubuntu 24.04 image by default
4. **Dry-run Support**: Test deployment without making changes
5. **Resource Listing**: View all resources before cleanup

## Troubleshooting

### VMs Not Starting

```bash
# Check libvirt daemon
sudo systemctl status libvirtd

# Check VM logs
virsh console hypervisor-1

# View VM details
virsh dominfo hypervisor-1
```

### Network Connectivity Issues

```bash
# Check network status
virsh net-list --all

# Restart management network
virsh net-destroy virtual-dc-lab-mgmt
virsh net-start virtual-dc-lab-mgmt

# Check bridge interfaces
ip link show type bridge
```

### BGP Not Establishing

```bash
# SSH into hypervisor
ssh -i config/virtual-dc-lab-ssh-key ubuntu@192.168.100.11

# Check FRR status
sudo systemctl status frr

# Check BGP configuration
sudo vtysh -c "show running-config"

# View BGP neighbors
sudo vtysh -c "show bgp summary"

# Check interface status
sudo vtysh -c "show interface brief"
```

## Project Structure

```
virtual-dc/
├── config/                 # Configuration files
│   ├── topology.yaml      # Main topology configuration
│   ├── cloud-init/        # Cloud-init configs for VMs
│   ├── bgp-configs/       # Generated BGP configurations
│   └── disks/             # VM disk images
├── scripts/               # Main deployment scripts
│   └── deploy-virtual-dc.sh
├── modules/               # Modular components
│   ├── validation.sh      # Configuration validation
│   ├── prerequisites.sh   # Dependency checking
│   ├── network.sh         # Network management
│   ├── hypervisor.sh      # Hypervisor deployment
│   ├── switches.sh        # Switch deployment
│   ├── bgp.sh             # BGP configuration
│   ├── cabling.sh         # Virtual cabling
│   └── verify.sh          # Deployment verification
├── templates/             # Configuration templates
├── examples/              # Example configurations
└── docs/                  # Additional documentation
```

## Advanced Topics

### Custom Topologies

Create your own topology by:

1. Copy the example configuration
2. Update the `topology_visual` ASCII art
3. Define your hypervisors and switches
4. Specify cabling layout
5. Validate and deploy

### Adding More Hypervisors

```yaml
hypervisors:
  - name: "hypervisor-5"
    short_name: "hv5"
    router_id: "1.1.1.5"
    asn: 65005
    management:
      ip: "192.168.100.15/24"
    data_interfaces:
      - name: "eth1"
```

### Multi-AS Design

Configure different AS numbers for different tiers:

```yaml
# Hypervisors in AS 65001-65999
hypervisors:
  - asn: 65001
  - asn: 65002

# Leafs in AS 65101-65199
switches:
  leaf:
    - asn: 65101
    - asn: 65102

# Spines in AS 65201-65299
switches:
  spine:
    - asn: 65201
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is part of the USVF (Universal Server Validation Framework) toolkit.

## Support

For issues, questions, or contributions:
- GitHub Issues: Report bugs and request features
- Documentation: See `/docs` directory for detailed guides

## Acknowledgments

- FRRouting project for BGP implementation
- SONiC project for network OS
- libvirt/KVM community for virtualization support
