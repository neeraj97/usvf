# VDC Manager Documentation

## Overview

The **VDC Manager** (Virtual Datacenter Manager) is a comprehensive tool for managing multiple isolated virtual datacenters on a single host machine. Each virtual datacenter (VDC) runs in its own network namespace, providing complete network isolation between different environments.

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Command Reference](#command-reference)
- [Use Cases](#use-cases)
- [Network Isolation](#network-isolation)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Features

### Core Capabilities

✅ **Multiple Isolated VDCs** - Run production, staging, and development environments simultaneously

✅ **Automatic Subnet Assignment** - Auto-assigns non-conflicting management subnets

✅ **Network Namespace Isolation** - Complete network isolation between VDCs

✅ **Resource Management** - Track and manage VMs, networks, and storage per VDC

✅ **Topology Visualization** - Display ASCII art topology diagrams

✅ **Orphan Cleanup** - Detect and remove orphaned resources

✅ **Status Monitoring** - Real-time status of all VDC resources

✅ **Registry-Based Tracking** - JSON registry for persistent VDC metadata

## Architecture

### VDC Isolation Model

```
┌─────────────────────────────────────────────────────────────────┐
│                         Host System                             │
│                                                                 │
│  ┌──────────────────────┐       ┌──────────────────────┐      │
│  │  VDC: Production     │       │  VDC: Staging        │      │
│  │  Namespace: vdc-prod │       │  Namespace: vdc-stag │      │
│  │  Subnet: 192.168.10  │       │  Subnet: 192.168.11  │      │
│  │                      │       │                      │      │
│  │  ┌────┐  ┌────┐     │       │  ┌────┐  ┌────┐     │      │
│  │  │HV1 │  │HV2 │     │       │  │HV1 │  │HV2 │     │      │
│  │  └────┘  └────┘     │       │  └────┘  └────┘     │      │
│  │     │  ╲  ╱│        │       │     │  ╲  ╱│        │      │
│  │  ┌──────────┐       │       │  ┌──────────┐       │      │
│  │  │ Leaf-1   │       │       │  │ Leaf-1   │       │      │
│  │  └──────────┘       │       │  └──────────┘       │      │
│  └──────────────────────┘       └──────────────────────┘      │
│                                                                 │
│  ┌──────────────────────┐                                      │
│  │  VDC: Development    │                                      │
│  │  Namespace: vdc-dev  │                                      │
│  │  Subnet: 192.168.12  │                                      │
│  │                      │                                      │
│  │  ┌────┐  ┌────┐     │                                      │
│  │  │HV1 │  │HV2 │     │                                      │
│  │  └────┘  └────┘     │                                      │
│  └──────────────────────┘                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Component Overview

| Component | Description | Location |
|-----------|-------------|----------|
| **vdc-manager.sh** | Main CLI tool | `scripts/vdc-manager.sh` |
| **vdc.sh** | VDC lifecycle management | `modules/vdc.sh` |
| **namespace.sh** | Network namespace operations | `modules/namespace.sh` |
| **Registry** | VDC metadata storage | `config/vdc-registry.json` |
| **VDC Configs** | Per-VDC configurations | `config/vdc-<name>/` |

## Installation

### Prerequisites

The VDC Manager requires the same prerequisites as the Virtual DC deployment:

- Ubuntu 24.04 LTS (recommended)
- KVM/QEMU with libvirt
- iproute2 (for network namespaces)
- jq, yq (JSON/YAML processing)
- Root/sudo access

### Setup

```bash
cd usvf/virtual-dc

# Check prerequisites
./scripts/deploy-virtual-dc.sh --check-prereqs

# Make VDC Manager executable (if not already)
chmod +x scripts/vdc-manager.sh
```

## Quick Start

### 1. List All VDCs

```bash
./scripts/vdc-manager.sh list
```

Output:
```
═══════════════════════════════════════════════════════════
              VIRTUAL DATACENTERS
═══════════════════════════════════════════════════════════

NAME                 NAMESPACE            CREATED                   STATUS          MANAGEMENT SUBNET
----                 ---------            -------                   ------          -----------------
prod                 vdc-prod             2026-01-21T10:00:00Z     running         192.168.10.0/24
staging              vdc-staging          2026-01-21T10:15:00Z     running         192.168.11.0/24

Total VDCs: 2
```

### 2. Create a New VDC

```bash
# Create with auto-assigned subnet
./scripts/vdc-manager.sh create \
  --name production \
  --config config/topology.yaml

# Create with custom subnet
./scripts/vdc-manager.sh create \
  --name staging \
  --config config/topology.yaml \
  --subnet 192.168.20.0/24
```

### 3. Check VDC Status

```bash
./scripts/vdc-manager.sh status --name production
```

### 4. View Resources

```bash
./scripts/vdc-manager.sh resources --name production
```

### 5. View Topology

```bash
./scripts/vdc-manager.sh topology --name production
```

### 6. Cleanup Orphans

```bash
# Scan for orphaned resources
./scripts/vdc-manager.sh cleanup-orphans --name production

# Force cleanup without confirmation
./scripts/vdc-manager.sh cleanup-orphans --name production --force
```

### 7. Destroy a VDC

```bash
# Interactive (asks for confirmation)
./scripts/vdc-manager.sh destroy --name production

# Force destroy
./scripts/vdc-manager.sh destroy --name production --force
```

## Command Reference

### `list`

Lists all registered virtual datacenters.

```bash
./scripts/vdc-manager.sh list
```

**Output includes:**
- VDC name
- Network namespace
- Creation timestamp
- Current status (running/stopped)
- Management subnet

---

### `create`

Creates a new virtual datacenter.

```bash
./scripts/vdc-manager.sh create --name <name> --config <file> [--subnet <subnet>]
```

**Parameters:**
- `--name <name>` - Unique name for the VDC (required)
- `--config <file>` - Path to topology YAML file (required)
- `--subnet <subnet>` - Management subnet in CIDR format (optional, auto-assigned if not provided)

**Example:**
```bash
./scripts/vdc-manager.sh create \
  --name prod \
  --config examples/leaf-spine.yaml \
  --subnet 192.168.50.0/24
```

**Process:**
1. Creates network namespace (`vdc-<name>`)
2. Registers VDC in registry
3. Copies and updates configuration
4. Deploys hypervisors and switches
5. Configures BGP routing

---

### `destroy`

Destroys a virtual datacenter and all its resources.

```bash
./scripts/vdc-manager.sh destroy --name <name> [--force]
```

**Parameters:**
- `--name <name>` - Name of VDC to destroy (required)
- `--force` - Skip confirmation prompt (optional)

**What gets destroyed:**
- All VMs (hypervisors and switches)
- All virtual networks
- All disk images
- Network namespace
- Cloud-init configurations
- VDC directory

**Example:**
```bash
# Interactive
./scripts/vdc-manager.sh destroy --name prod

# Force (no confirmation)
./scripts/vdc-manager.sh destroy --name prod --force
```

---

### `status`

Shows detailed status of a VDC.

```bash
./scripts/vdc-manager.sh status --name <name>
```

**Displays:**
- VDC metadata (name, namespace, creation time)
- Network namespace status
- VM states and resources
- Network status
- Bridge interfaces

**Example:**
```bash
./scripts/vdc-manager.sh status --name prod
```

---

### `resources`

Lists all resources in a VDC with detailed information.

```bash
./scripts/vdc-manager.sh resources --name <name>
```

**Shows:**
- **Hypervisors:** Name, state, vCPU, memory, management IP
- **Switches:** Name, state, vCPU, memory, management IP
- **Disk Usage:** Total disks, total size

**Example:**
```bash
./scripts/vdc-manager.sh resources --name prod
```

---

### `topology`

Displays the network topology of a VDC.

```bash
./scripts/vdc-manager.sh topology --name <name>
```

**Displays:**
- ASCII art topology diagram
- Cabling layout table
- Device connections

**Example:**
```bash
./scripts/vdc-manager.sh topology --name prod
```

---

### `cleanup-orphans`

Finds and removes orphaned resources in a VDC.

```bash
./scripts/vdc-manager.sh cleanup-orphans --name <name> [--force]
```

**Detects:**
- VMs not defined in topology config
- Networks not expected for the VDC
- Disk images without associated VMs

**Parameters:**
- `--name <name>` - VDC to scan (required)
- `--force` - Cleanup without confirmation (optional)

**Example:**
```bash
# Scan and prompt
./scripts/vdc-manager.sh cleanup-orphans --name prod

# Force cleanup
./scripts/vdc-manager.sh cleanup-orphans --name prod --force
```

---

## Use Cases

### 1. Multi-Environment Setup

Run production, staging, and development environments simultaneously:

```bash
# Production VDC
./scripts/vdc-manager.sh create \
  --name prod \
  --config topologies/production.yaml

# Staging VDC
./scripts/vdc-manager.sh create \
  --name staging \
  --config topologies/staging.yaml

# Development VDC
./scripts/vdc-manager.sh create \
  --name dev \
  --config topologies/development.yaml
```

### 2. Testing Different Topologies

Test various network designs in isolation:

```bash
# Leaf-Spine topology
./scripts/vdc-manager.sh create \
  --name test-leaf-spine \
  --config topologies/leaf-spine.yaml

# Full mesh topology
./scripts/vdc-manager.sh create \
  --name test-full-mesh \
  --config topologies/full-mesh.yaml
```

### 3. Training and Demonstrations

Create temporary environments for training:

```bash
# Create training environment
./scripts/vdc-manager.sh create \
  --name training-day1 \
  --config training/basic-topology.yaml

# After training, destroy
./scripts/vdc-manager.sh destroy --name training-day1 --force
```

### 4. CI/CD Testing

Automated testing in isolated environments:

```bash
#!/bin/bash
# CI/CD test script

VDC_NAME="ci-test-${BUILD_ID}"

# Create test environment
./scripts/vdc-manager.sh create \
  --name "$VDC_NAME" \
  --config test/topology.yaml

# Run tests
# ... your tests here ...

# Cleanup
./scripts/vdc-manager.sh destroy --name "$VDC_NAME" --force
```

## Network Isolation

### How Isolation Works

Each VDC runs in its own **Linux network namespace**, providing:

1. **Separate Network Stack**
   - Independent routing tables
   - Separate iptables rules
   - Isolated ARP cache

2. **Non-Overlapping IPs**
   - Each VDC gets unique management subnet
   - Auto-assignment prevents conflicts
   - No IP collision between VDCs

3. **Independent Resources**
   - VMs are prefixed with VDC name (`prod-hv1`, `staging-hv1`)
   - Networks are VDC-specific (`prod-mgmt`, `staging-mgmt`)
   - Separate disk images and configurations

### Namespace Benefits

```bash
# List all namespaces
ip netns list

# Execute command in specific namespace
sudo ip netns exec vdc-prod ip addr show

# View routing table in namespace
sudo ip netns exec vdc-prod ip route show
```

### Management Subnet Assignment

The VDC Manager automatically assigns management subnets in the `192.168.x.0/24` range:

| VDC Order | Auto-Assigned Subnet |
|-----------|---------------------|
| 1st VDC   | 192.168.10.0/24     |
| 2nd VDC   | 192.168.11.0/24     |
| 3rd VDC   | 192.168.12.0/24     |
| ...       | ...                 |

You can override with `--subnet` parameter if needed.

## Troubleshooting

### VDC Not Starting

**Problem:** VDC creation fails

**Solution:**
```bash
# Check prerequisites
./scripts/deploy-virtual-dc.sh --check-prereqs

# Check available resources
free -h
df -h

# Check libvirt
sudo systemctl status libvirtd
```

### Namespace Issues

**Problem:** Namespace not created or accessible

**Solution:**
```bash
# List all namespaces
sudo ip netns list

# Check if namespace exists
sudo ip netns list | grep vdc-

# Manually create namespace (if needed)
sudo ip netns add vdc-test

# Delete stuck namespace
sudo ip netns del vdc-test
```

### Orphaned Resources

**Problem:** Resources exist but VDC doesn't list them

**Solution:**
```bash
# Run orphan cleanup
./scripts/vdc-manager.sh cleanup-orphans --name <vdc-name>

# Manually check for orphaned VMs
virsh list --all | grep <vdc-name>

# Manually check for orphaned networks
virsh net-list --all | grep <vdc-name>
```

### Registry Corruption

**Problem:** VDC registry is corrupted or invalid

**Solution:**
```bash
# Backup current registry
cp config/vdc-registry.json config/vdc-registry.json.backup

# Validate JSON
jq . config/vdc-registry.json

# Rebuild registry manually if needed
cat > config/vdc-registry.json <<EOF
{
  "version": "1.0",
  "virtual_datacenters": []
}
EOF
```

### Subnet Conflicts

**Problem:** Management subnet conflicts

**Solution:**
```bash
# List current subnet assignments
jq '.virtual_datacenters[].management_subnet' config/vdc-registry.json

# Manually specify non-conflicting subnet
./scripts/vdc-manager.sh create \
  --name newvdc \
  --config topology.yaml \
  --subnet 192.168.100.0/24
```

## Best Practices

### 1. Naming Conventions

Use descriptive, consistent names:
```bash
# Good
./scripts/vdc-manager.sh create --name prod-us-east-1 ...
./scripts/vdc-manager.sh create --name staging-v2 ...

# Avoid
./scripts/vdc-manager.sh create --name test123 ...
```

### 2. Resource Planning

Plan your resources before creating multiple VDCs:

```bash
# Check available resources
free -h           # Memory
df -h             # Disk
nproc             # CPUs
```

**Recommended per VDC:**
- 4GB RAM minimum
- 10GB disk space per VM
- 2 vCPUs per VM

### 3. Regular Cleanup

Periodically clean up unused VDCs:

```bash
# List all VDCs
./scripts/vdc-manager.sh list

# Destroy unused ones
./scripts/vdc-manager.sh destroy --name old-test --force

# Check for orphans in remaining VDCs
for vdc in $(jq -r '.virtual_datacenters[].name' config/vdc-registry.json); do
    ./scripts/vdc-manager.sh cleanup-orphans --name "$vdc"
done
```

### 4. Configuration Management

Keep topology configurations in version control:

```bash
# Organized structure
topologies/
  ├── production.yaml
  ├── staging.yaml
  ├── development.yaml
  └── templates/
      ├── small-lab.yaml
      └── large-scale.yaml
```

### 5. Monitoring

Monitor VDC resources:

```bash
# Create monitoring script
cat > monitor-vdcs.sh <<'EOF'
#!/bin/bash
for vdc in $(jq -r '.virtual_datacenters[].name' config/vdc-registry.json); do
    echo "=== VDC: $vdc ==="
    ./scripts/vdc-manager.sh status --name "$vdc"
    echo ""
done
EOF

chmod +x monitor-vdcs.sh
```

### 6. Backup Strategy

Backup VDC configurations:

```bash
# Backup script
#!/bin/bash
BACKUP_DIR="backups/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# Backup registry
cp config/vdc-registry.json "$BACKUP_DIR/"

# Backup VDC configs
cp -r config/vdc-* "$BACKUP_DIR/"

echo "Backup created in $BACKUP_DIR"
```

## Advanced Usage

### Scripting with VDC Manager

```bash
#!/bin/bash
# Example: Create ephemeral test environment

VDC_NAME="test-$(date +%s)"

# Create
./scripts/vdc-manager.sh create \
  --name "$VDC_NAME" \
  --config test-topology.yaml

# Wait for deployment
sleep 60

# Run tests
echo "Running tests in VDC: $VDC_NAME"
# ... test commands ...

# Cleanup
./scripts/vdc-manager.sh destroy --name "$VDC_NAME" --force
```

### Integration with CI/CD

```yaml
# GitHub Actions example
name: Network Tests

on: [push]

jobs:
  test:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v2
      
      - name: Setup VDC
        run: |
          cd usvf/virtual-dc
          ./scripts/vdc-manager.sh create \
            --name ci-${{ github.run_id }} \
            --config test/topology.yaml
      
      - name: Run Tests
        run: |
          # Your network tests here
          
      - name: Cleanup
        if: always()
        run: |
          cd usvf/virtual-dc
          ./scripts/vdc-manager.sh destroy \
            --name ci-${{ github.run_id }} \
            --force
```

## Registry Format

The VDC registry (`config/vdc-registry.json`) structure:

```json
{
  "version": "1.0",
  "virtual_datacenters": [
    {
      "name": "production",
      "namespace": "vdc-production",
      "created_at": "2026-01-21T10:00:00Z",
      "status": "running",
      "management_subnet": "192.168.10.0/24",
      "config_file": "config/vdc-production/topology.yaml",
      "vms": [],
      "networks": [],
      "switches": []
    }
  ]
}
```

## Support

For issues or questions:
- Check this documentation
- Review troubleshooting section
- Check main README: `usvf/virtual-dc/README.md`
- Examine log files in `config/vdc-<name>/`

## Related Documentation

- [Main README](../README.md) - Virtual DC overview
- [SONiC Deployment](SONIC_DEPLOYMENT.md) - SONiC switch details
- [Quick Start Guide](../QUICKSTART.md) - Getting started

---

**VDC Manager Version:** 1.0  
**Last Updated:** January 2026
