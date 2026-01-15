# Ubuntu OS Repacker

A comprehensive tool for repacking Ubuntu 24.04 ISO images with pre-configured packages and BGP routing for Mellanox network interfaces.

## Overview

This tool automates the process of:
- Extracting Ubuntu 24.04 ISO images
- Installing essential packages (OpenStack, FRR, net-tools, debugging tools)
- Configuring BGP routing for Mellanox network interfaces
- Repacking the customized OS into a new ISO image

## Architecture

The OS Repacker uses a **modular two-stage architecture with cloud-init**:

- **Stage 1 (stage1-packages.sh)**: Package installation only
  - Installs default and custom packages (including cloud-init)
  - Creates a reusable base ISO
  - No network configuration

- **Stage 2 (stage2-network.sh)**: Network & BGP configuration using cloud-init
  - **Two modes available:**
    1. **ISO Mode**: Embeds cloud-init configuration into ISO
    2. **Cloud-Init Only Mode**: Generates standalone cloud-init files (no ISO needed)
  - Uses industry-standard cloud-init instead of custom systemd services
  - All scripts embedded in cloud-init user-data
  - Can be applied to any Ubuntu ISO (including Stage 1 output)

- **All-in-One (repack-os.sh)**: Backward compatible wrapper
  - Internally calls Stage 1 → Stage 2
  - Same interface as original monolithic script
  - Best for simple, one-off deployments

## Features

- **Modular Design**: Use stages individually or together
- **Cloud-Init Integration**: Industry-standard configuration management
- **Flexible Deployment**: ISO mode or standalone cloud-init files
- **Package Installation**: Automatic installation of OpenStack, FRR, net-tools, and debugging utilities
- **Custom Packages**: Support for user-specified additional packages
- **BGP Configuration**: Automatic BGP configuration for Mellanox interfaces via cloud-init
- **Reusable Base ISOs**: Create one package ISO, deploy with multiple network configs
- **Standalone Cloud-Init**: Generate cloud-init files without ISO processing
- **Automated ISO Repacking**: Complete ISO extraction, customization, and repacking workflow
- **Ubuntu 24.04 Support**: Designed specifically for Ubuntu 24.04

## Prerequisites

- Ubuntu 24.04 host system
- Root/sudo privileges
- Minimum 20GB free disk space
- Required tools: xorriso, squashfs-tools, genisoimage

## Quick Start

### Option 1: All-in-One (Simplest)

```bash
# Install dependencies
sudo ./install-deps.sh

# Repack ISO with packages and network config in one command
sudo ./repack-os.sh \
  --iso ubuntu-24.04.iso \
  --output custom-ubuntu.iso \
  --local-asn 65001 \
  --router-id 1.1.1.1 \
  --packages "vim,htop,iperf3" \
  --bgp-config bgp-peers.conf \
  --bgp-networks "10.0.0.0/24,192.168.1.0/24"
```

### Option 2: Two-Stage (Most Flexible)

```bash
# Install dependencies
sudo ./install-deps.sh

# Stage 1: Create base ISO with packages (once)
sudo ./stage1-packages.sh \
  --iso ubuntu-24.04.iso \
  --output base-ubuntu.iso \
  --packages "vim,htop,iperf3"

# Stage 2 ISO Mode: Add network config (create multiple from same base)
sudo ./stage2-network.sh \
  --iso base-ubuntu.iso \
  --output dc1-ubuntu.iso \
  --local-asn 65001 \
  --router-id 10.1.0.1 \
  --bgp-config dc1-peers.conf \
  --bgp-networks "10.1.0.0/24"

sudo ./stage2-network.sh \
  --iso base-ubuntu.iso \
  --output dc2-ubuntu.iso \
  --local-asn 65002 \
  --router-id 10.2.0.1 \
  --bgp-config dc2-peers.conf \
  --bgp-networks "10.2.0.0/24"
```

### Option 3: Cloud-Init Only Mode (Maximum Flexibility)

```bash
# Generate standalone cloud-init files (no ISO needed)
sudo ./stage2-network.sh \
  --cloud-init-only \
  --output-dir dc1-config \
  --local-asn 65001 \
  --router-id 10.1.0.1 \
  --bgp-config dc1-peers.conf \
  --bgp-networks "10.1.0.0/24"

# Use generated files with any Ubuntu installation
# Option A: Create config ISO
cloud-localds config.iso dc1-config/user-data dc1-config/meta-data

# Option B: Copy to existing system
sudo cp dc1-config/* /var/lib/cloud/seed/nocloud-net/
sudo cloud-init clean && sudo cloud-init init

# Option C: HTTP datasource (setup web server to serve files)
# Boot with: ds=nocloud-net;s=http://your-server/dc1-config/
```

## BGP Configuration

### BGP Peers Configuration File

Create a BGP peers configuration file (e.g., `bgp-peers.conf`):

```
# Format: remote_asn,remote_ip,local_ip
# Peers are automatically assigned to Mellanox interfaces in detection order
65002,192.168.1.1,192.168.1.2
65003,192.168.2.1,192.168.2.2
```

**How it works:**
- The first peer is assigned to the first detected Mellanox interface
- The second peer is assigned to the second detected Mellanox interface
- And so on...
- No need to specify interface names - they're auto-detected and assigned

### BGP Network Advertisement

**IMPORTANT**: By default, NO networks are advertised. You must explicitly specify networks to advertise using the `--bgp-networks` parameter:

```bash
# Advertise specific networks
--bgp-networks "10.0.0.0/24,192.168.1.0/24,172.16.0.0/16"
```

Networks should be in CIDR notation and comma-separated. These networks will be advertised to all BGP peers.

## Directory Structure

```
os-repacker/
├── repack-os.sh                      # All-in-one wrapper (backward compatible)
├── stage1-packages.sh                # Stage 1: Package installation
├── stage2-network.sh                 # Stage 2: Network & BGP (cloud-init mode)
├── install-deps.sh                   # Dependency installation
├── modules/
│   ├── iso-extract.sh                # ISO extraction module
│   ├── package-install.sh            # Package installation module
│   ├── cloud-init-generator.sh       # Cloud-init user-data generator
│   ├── mellanox-detect-script.sh     # Mellanox detection (embedded in cloud-init)
│   ├── bgp-config-script.sh          # BGP configuration (embedded in cloud-init)
│   └── iso-repack.sh                 # ISO repacking module
├── examples/
│   └── bgp-peers.conf.example
└── README.md
```

## Usage Examples

### All-in-One Approach

**Best for**: Simple deployments, one-off customizations, small scale

```bash
# Basic repacking
sudo ./repack-os.sh \
  --iso ubuntu-24.04-server-amd64.iso \
  --output custom-ubuntu.iso \
  --local-asn 65001 \
  --router-id 1.1.1.1

# With custom packages
sudo ./repack-os.sh \
  --iso ubuntu-24.04-server-amd64.iso \
  --output custom-ubuntu.iso \
  --packages "tcpdump,wireshark,stress-ng,sysstat" \
  --local-asn 65001 \
  --router-id 10.0.0.1 \
  --bgp-config my-bgp-peers.conf

# With BGP configuration and network advertisement
cat > bgp-peers.conf << EOF
65100,10.0.1.1,10.0.1.2
65200,10.0.2.1,10.0.2.2
EOF

sudo ./repack-os.sh \
  --iso ubuntu-24.04-server-amd64.iso \
  --output bgp-ubuntu.iso \
  --local-asn 65001 \
  --router-id 192.168.1.1 \
  --bgp-config bgp-peers.conf \
  --bgp-networks "10.0.0.0/24,192.168.1.0/24"
```

### Two-Stage Approach

**Best for**: Multiple deployments, different network configs, large scale

#### Stage 1: Create Reusable Base ISO

```bash
# Basic base with default packages
sudo ./stage1-packages.sh \
  --iso ubuntu-24.04-server-amd64.iso \
  --output base-ubuntu.iso

# With additional packages
sudo ./stage1-packages.sh \
  --iso ubuntu-24.04-server-amd64.iso \
  --output base-ubuntu-dev.iso \
  --packages "docker.io,kubernetes-client,ansible,vim,tmux,htop"

# With custom work directory
sudo ./stage1-packages.sh \
  --iso ubuntu-24.04-server-amd64.iso \
  --output /mnt/isos/base-ubuntu.iso \
  --work-dir /mnt/ssd/work \
  --verbose
```

#### Stage 2: Add Network Configuration

```bash
# Create multiple datacenter ISOs from same base
cat > dc1-peers.conf << EOF
65100,10.1.1.1,10.1.1.2
65101,10.1.2.1,10.1.2.2
EOF

cat > dc2-peers.conf << EOF
65200,10.2.1.1,10.2.1.2
65201,10.2.2.1,10.2.2.2
EOF

# Datacenter 1 ISO
sudo ./stage2-network.sh \
  --iso base-ubuntu.iso \
  --output dc1-ubuntu.iso \
  --local-asn 65001 \
  --router-id 10.1.0.1 \
  --bgp-config dc1-peers.conf \
  --bgp-networks "10.1.0.0/16"

# Datacenter 2 ISO
sudo ./stage2-network.sh \
  --iso base-ubuntu.iso \
  --output dc2-ubuntu.iso \
  --local-asn 65002 \
  --router-id 10.2.0.1 \
  --bgp-config dc2-peers.conf \
  --bgp-networks "10.2.0.0/16"

# Test environment (no BGP peers, just network detection)
sudo ./stage2-network.sh \
  --iso base-ubuntu.iso \
  --output test-ubuntu.iso \
  --local-asn 65099 \
  --router-id 192.168.99.1
```

### When to Use Which Approach

| Scenario | Recommended Approach | Reason |
|----------|---------------------|--------|
| Single server deployment | All-in-One | Simplest, one command |
| Multiple servers, same config | All-in-One | Consistent, easy to reproduce |
| Multiple servers, different BGP configs | Two-Stage ISO Mode | Build base once, reuse for different networks |
| Multiple datacenters | Two-Stage ISO Mode | One base ISO, many network configs |
| Testing different BGP configurations | Cloud-Init Only Mode | Fast iteration, no ISO rebuild |
| Existing Ubuntu installations | Cloud-Init Only Mode | Apply config to running systems |
| Orchestration/automation systems | Cloud-Init Only Mode | Generate configs, deploy programmatically |
| HTTP-based deployment | Cloud-Init Only Mode | Serve cloud-init from web server |
| Frequent package updates | Two-Stage | Update base ISO, re-apply network configs |
| Large scale deployment (100+ servers) | Two-Stage + Cloud-Init | Efficiency, consistency, flexibility |

## Default Packages

The following packages are installed by default:
- **OpenStack**: Complete OpenStack installation
- **FRR**: Free Range Routing (BGP, OSPF, etc.)
- **net-tools**: Network utilities (ifconfig, netstat, etc.)
- **Debugging Tools**: 
  - tcpdump, wireshark-cli
  - strace, ltrace
  - sysstat (sar, iostat, mpstat)
  - htop, iotop
  - lsof, netcat
  - ethtool, iproute2
  - traceroute, mtr
  - curl, wget
  - vim, nano

## Important Notes

### BGP Network Advertisement
- **By default, NO networks are advertised** - you must explicitly configure them
- Use `--bgp-networks` parameter to specify networks to advertise in CIDR format
- Networks are advertised to all configured BGP peers
- Example: `--bgp-networks "10.0.0.0/24,192.168.1.0/24,172.16.0.0/16"`

### General Notes
- The script requires root privileges for ISO manipulation
- Ensure sufficient disk space (at least 20GB recommended)
- Original ISO file is not modified
- BGP configuration is applied during first boot via systemd service
- Only Mellanox network interfaces are configured for BGP
- All Mellanox interfaces must be connected and properly cabled for BGP to function

## Troubleshooting

### Issue: Insufficient disk space
**Solution**: Free up at least 20GB of disk space before running the repacker

### Issue: Missing dependencies
**Solution**: Run `sudo ./install-deps.sh` to install all required tools

### Issue: BGP not configured
**Solution**: Verify BGP configuration file format and ensure Mellanox interfaces are present

## License

Part of the USVF (Unified Server Validation Framework) toolkit.
