# Ubuntu OS Repacker - Usage Guide

## Table of Contents
1. [Introduction](#introduction)
2. [Architecture Overview](#architecture-overview)
3. [Prerequisites](#prerequisites)
4. [Installation](#installation)
5. [Basic Usage](#basic-usage)
6. [Two-Stage Usage](#two-stage-usage)
7. [Cloud-Init Only Mode](#cloud-init-only-mode)
8. [Advanced Configuration](#advanced-configuration)
9. [BGP Configuration](#bgp-configuration)
10. [Troubleshooting](#troubleshooting)
11. [Examples](#examples)

## Introduction

The Ubuntu OS Repacker is a powerful tool for creating customized Ubuntu 24.04 ISO images with pre-installed packages and BGP configuration for Mellanox network interfaces. This is particularly useful for deployment scenarios where you need standardized server configurations with networking capabilities.

The tool offers both **all-in-one** and **modular two-stage** approaches, allowing you to choose the workflow that best fits your needs.

## Architecture Overview

### Four Ways to Use the OS Repacker

#### 1. All-in-One Mode (repack-os.sh)
- **Best for**: Simple deployments, one-off customizations
- **Process**: Packages + Network config in one command
- **Output**: One final ISO ready to deploy
- **Technology**: Embeds cloud-init configuration in ISO

#### 2. Two-Stage ISO Mode
- **Best for**: Multiple deployments with different network configs
- **Process**: 
  - Stage 1 (stage1-packages.sh): Install packages → Base ISO
  - Stage 2 (stage2-network.sh --iso): Add network config → Final ISO(s)
- **Output**: One reusable base ISO + multiple network-configured ISOs
- **Technology**: Cloud-init embedded in ISO

#### 3. Cloud-Init Only Mode (NEW!)
- **Best for**: Existing systems, HTTP deployment, orchestration
- **Process**: Stage 2 (stage2-network.sh --cloud-init-only): Generate cloud-init files
- **Output**: user-data and meta-data files (no ISO needed!)
- **Technology**: Standalone cloud-init files for any Ubuntu 24.04
- **Use Cases**:
  - Apply config to existing Ubuntu installations
  - HTTP-based cloud-init deployment
  - ConfigDrive for OpenStack/cloud platforms
  - Automation and orchestration systems
  - Testing configurations without ISO rebuilds

#### 4. Individual Stages
- **Best for**: Maximum flexibility and customization
- **Process**: Use Stage 1 OR Stage 2 independently
- **Use Cases**:
  - Stage 1 only: Create package-only ISO without network config
  - Stage 2 ISO mode: Add network config to existing Ubuntu ISO
  - Stage 2 cloud-init mode: Generate standalone configuration files

### Modular Architecture Benefits

**Reusability**
- Build base package ISO once
- Create multiple network configurations from same base
- Generate cloud-init files for any deployment method
- Save time on package installation

**Flexibility**
- Different BGP configs for different datacenters
- Test configurations without rebuilding packages
- Easy updates: rebuild base, re-apply network configs
- Deploy via ISO, cloud-init, or both

**Cloud-Init Integration**
- Industry-standard configuration management
- All scripts embedded in cloud-init user-data
- Better debugging with cloud-init logs
- Extensible with full cloud-init ecosystem
- No custom systemd services needed

**Efficiency**
- Package installation is slow (Stage 1 once)
- Network configuration is fast (Stage 2 many times)
- Cloud-init generation is instant (seconds)
- Reduced ISO storage (one base + small network configs)

**Scalability**
- Manage 100+ servers with different network configs
- Single source of truth for base packages
- Consistent package versions across all deployments
- HTTP-based deployment for massive scale

## Prerequisites

### System Requirements
- **Operating System**: Ubuntu 24.04 (host system)
- **Privileges**: Root/sudo access
- **Disk Space**: Minimum 20GB free space
- **Memory**: At least 4GB RAM recommended
- **CPU**: Multi-core processor recommended for faster processing

### Required Tools
The following tools will be installed automatically by `install-deps.sh`:
- xorriso
- squashfs-tools
- genisoimage
- isolinux
- syslinux-utils
- rsync
- Other utilities

## Installation

### Step 1: Navigate to Directory
```bash
cd /path/to/usvf/os-repacker
```

### Step 2: Install Dependencies
```bash
sudo ./install-deps.sh
```

This will:
- Verify you're running Ubuntu 24.04
- Install all required tools
- Verify the installation

### Step 3: Verify Installation
The script will automatically verify all required commands are available. You should see:
```
[SUCCESS] All required commands are available
[SUCCESS] Installation completed successfully!
```

## Basic Usage

### All-in-One Mode (repack-os.sh)

This mode combines package installation and network configuration in a single command.

#### Simple Repacking with Default Packages

```bash
sudo ./repack-os.sh \
  --iso ubuntu-24.04-server-amd64.iso \
  --output custom-ubuntu.iso \
  --local-asn 65001 \
  --router-id 10.0.0.1
```

This will create a customized ISO with:
- OpenStack packages
- FRR (BGP routing)
- net-tools
- Comprehensive debugging tools
- Mellanox interface detection
- BGP configuration ready

#### Adding Custom Packages

```bash
sudo ./repack-os.sh \
  --iso ubuntu-24.04.iso \
  --output custom.iso \
  --local-asn 65001 \
  --router-id 10.0.0.1 \
  --packages "vim,htop,iperf3,tcpdump,stress-ng"
```

## Two-Stage Usage

### When to Use Two-Stage Approach

Use the two-stage approach when you need:
- **Multiple network configurations** from the same base packages
- **Different datacenter deployments** with different BGP configs
- **Frequent network config changes** without rebuilding packages
- **Large-scale deployments** (100+ servers)
- **Testing** different BGP configurations quickly

### Stage 1: Package Installation (stage1-packages.sh)

Stage 1 creates a base Ubuntu ISO with all required packages installed, but no network configuration.

#### Stage 1 Command-Line Options

| Option | Required | Description |
|--------|----------|-------------|
| `--iso FILE` | Yes | Path to input Ubuntu 24.04 ISO file |
| `--output FILE` | Yes | Path for output base ISO file |
| `--packages LIST` | No | Comma-separated additional packages |
| `--work-dir DIR` | No | Custom working directory |
| `--verbose` | No | Enable verbose output |
| `-h, --help` | No | Show help message |

#### Stage 1 Examples

**Basic base ISO with default packages:**
```bash
sudo ./stage1-packages.sh \
  --iso ubuntu-24.04-server-amd64.iso \
  --output base-ubuntu.iso
```

**Base ISO with custom packages:**
```bash
sudo ./stage1-packages.sh \
  --iso ubuntu-24.04-server-amd64.iso \
  --output base-dev-ubuntu.iso \
  --packages "docker.io,kubernetes-client,ansible,vim,tmux,htop,iperf3"
```

**With custom work directory and verbose output:**
```bash
sudo ./stage1-packages.sh \
  --iso ubuntu-24.04-server-amd64.iso \
  --output /mnt/isos/base-ubuntu.iso \
  --work-dir /mnt/ssd/stage1-work \
  --verbose
```

#### What Stage 1 Does

1. Extracts the input Ubuntu ISO
2. Installs default packages:
   - OpenStack components
   - FRR routing daemon
   - Network tools
   - Debugging utilities
   - Development tools
3. Installs any custom packages you specified
4. Repacks into a new base ISO
5. **Does NOT** configure network or BGP

#### Stage 1 Output

The output is a **reusable base ISO** that contains all packages but no network-specific configuration. This base ISO can be used as input to Stage 2 multiple times with different network configurations.

### Stage 2: Network & BGP Configuration (stage2-network.sh)

Stage 2 takes ANY Ubuntu ISO (including Stage 1 output or vanilla Ubuntu) and adds Mellanox detection and BGP configuration.

#### Stage 2 Command-Line Options

| Option | Required | Description |
|--------|----------|-------------|
| `--iso FILE` | Yes | Path to input ISO (can be Stage 1 output or any Ubuntu ISO) |
| `--output FILE` | Yes | Path for output ISO file |
| `--local-asn ASN` | Yes | Local BGP AS number (1-4294967295) |
| `--router-id IP` | Yes | BGP router ID (IP address format) |
| `--bgp-config FILE` | No | BGP peers configuration file |
| `--bgp-networks LIST` | No | Networks to advertise (CIDR, comma-separated) |
| `--work-dir DIR` | No | Custom working directory |
| `--verbose` | No | Enable verbose output |
| `-h, --help` | No | Show help message |

#### Stage 2 Examples

**Add BGP config to base ISO:**
```bash
cat > dc1-peers.conf << EOF
65100,10.1.1.1,10.1.1.2
65101,10.1.2.1,10.1.2.2
EOF

sudo ./stage2-network.sh \
  --iso base-ubuntu.iso \
  --output dc1-ubuntu.iso \
  --local-asn 65001 \
  --router-id 10.1.0.1 \
  --bgp-config dc1-peers.conf \
  --bgp-networks "10.1.0.0/16"
```

**Create multiple datacenter ISOs from same base:**
```bash
# Datacenter 1
sudo ./stage2-network.sh \
  --iso base-ubuntu.iso \
  --output dc1-ubuntu.iso \
  --local-asn 65001 \
  --router-id 10.1.0.1 \
  --bgp-config dc1-peers.conf \
  --bgp-networks "10.1.0.0/16"

# Datacenter 2
sudo ./stage2-network.sh \
  --iso base-ubuntu.iso \
  --output dc2-ubuntu.iso \
  --local-asn 65002 \
  --router-id 10.2.0.1 \
  --bgp-config dc2-peers.conf \
  --bgp-networks "10.2.0.0/16"

# Datacenter 3
sudo ./stage2-network.sh \
  --iso base-ubuntu.iso \
  --output dc3-ubuntu.iso \
  --local-asn 65003 \
  --router-id 10.3.0.1 \
  --bgp-config dc3-peers.conf \
  --bgp-networks "10.3.0.0/16"
```

**Test environment (minimal BGP config):**
```bash
sudo ./stage2-network.sh \
  --iso base-ubuntu.iso \
  --output test-ubuntu.iso \
  --local-asn 65099 \
  --router-id 192.168.99.1
```

#### What Stage 2 Does

1. Extracts the input ISO (can be Stage 1 output)
2. Adds Mellanox interface detection scripts
3. Adds BGP configuration scripts
4. Embeds BGP peer configuration (if provided)
5. Embeds network advertisement configuration (if provided)
6. Creates systemd services for auto-configuration on boot
7. Repacks into final ISO

#### Stage 2 Output

The output is a **deployment-ready ISO** with network configuration embedded. When you boot from this ISO, the system will:
1. Detect Mellanox network interfaces
2. Configure BGP on those interfaces
3. Establish BGP sessions with configured peers
4. Advertise specified networks

### Complete Two-Stage Workflow

Here's a complete example showing the power of the two-stage approach:

```bash
# Step 1: Create base ISO once
sudo ./stage1-packages.sh \
  --iso ubuntu-24.04-server-amd64.iso \
  --output base-ubuntu.iso \
  --packages "docker.io,vim,htop,iperf3"

# Step 2: Create BGP peer configs for different locations
cat > dc1-peers.conf << EOF
65100,10.1.1.1,10.1.1.2
65101,10.1.2.1,10.1.2.2
EOF

cat > dc2-peers.conf << EOF
65200,10.2.1.1,10.2.1.2
65201,10.2.2.1,10.2.2.2
EOF

cat > dc3-peers.conf << EOF
65300,10.3.1.1,10.3.1.2
65301,10.3.2.1,10.3.2.2
EOF

# Step 3: Create datacenter-specific ISOs from same base
sudo ./stage2-network.sh \
  --iso base-ubuntu.iso \
  --output dc1-prod.iso \
  --local-asn 65001 \
  --router-id 10.1.0.1 \
  --bgp-config dc1-peers.conf \
  --bgp-networks "10.1.0.0/16,172.16.1.0/24"

sudo ./stage2-network.sh \
  --iso base-ubuntu.iso \
  --output dc2-prod.iso \
  --local-asn 65002 \
  --router-id 10.2.0.1 \
  --bgp-config dc2-peers.conf \
  --bgp-networks "10.2.0.0/16,172.16.2.0/24"

sudo ./stage2-network.sh \
  --iso base-ubuntu.iso \
  --output dc3-prod.iso \
  --local-asn 65003 \
  --router-id 10.3.0.1 \
  --bgp-config dc3-peers.conf \
  --bgp-networks "10.3.0.0/16,172.16.3.0/24"
```

**Result**: 
- 1 base ISO (packages installed once)
- 3 datacenter-specific ISOs (created in minutes each)
- All ISOs share same package versions
- Easy to update: rebuild base, re-run Stage 2 for all datacenters

### Approach Comparison

| Feature | All-in-One | Two-Stage |
|---------|-----------|-----------|
| **Simplicity** | ✅ Single command | ⚠️ Two commands |
| **Speed (single deployment)** | ✅ Fast | ⚠️ Slightly slower |
| **Speed (multiple deployments)** | ❌ Slow | ✅ Very fast |
| **Flexibility** | ❌ Limited | ✅ High |
| **Reusability** | ❌ None | ✅ Excellent |
| **Storage efficiency** | ❌ Many full ISOs | ✅ One base + deltas |
| **Best for** | 1-5 servers | 10+ servers |
| **Configuration changes** | ❌ Full rebuild | ✅ Quick Stage 2 only |
| **Testing iterations** | ❌ Slow | ✅ Fast |
| **Learning curve** | ✅ Easy | ⚠️ Moderate |

### Decision Flowchart

```
Do you need BGP configuration?
│
├─ No ─────────────────────────────────► Use Stage 1 only
│                                        (base-ubuntu.iso)
│
└─ Yes
   │
   How many different network configs?
   │
   ├─ One ─────────────────────────────► Use All-in-One
   │                                      (repack-os.sh)
   │
   └─ Multiple
      │
      Will configs change frequently?
      │
      ├─ No ──────────────────────────► Use All-in-One
      │                                  (acceptable)
      │
      └─ Yes ─────────────────────────► Use Two-Stage
                                         (stage1 + stage2)

Additional Factors:
- More than 10 servers? → Two-Stage
- Testing configurations? → Two-Stage
- One-off deployment? → All-in-One
- Need version consistency? → Two-Stage
```

### Time Comparison Example

**Scenario**: Deploy to 5 datacenters with different BGP configs

**All-in-One Approach:**
```
Build DC1 ISO: 30 minutes
Build DC2 ISO: 30 minutes
Build DC3 ISO: 30 minutes
Build DC4 ISO: 30 minutes
Build DC5 ISO: 30 minutes
─────────────────────────
Total Time: 150 minutes (2.5 hours)
```

**Two-Stage Approach:**
```
Build Base ISO (Stage 1): 30 minutes
Add DC1 config (Stage 2): 5 minutes
Add DC2 config (Stage 2): 5 minutes
Add DC3 config (Stage 2): 5 minutes
Add DC4 config (Stage 2): 5 minutes
Add DC5 config (Stage 2): 5 minutes
─────────────────────────
Total Time: 55 minutes

Time Saved: 95 minutes (63% faster!)
```

## Cloud-Init Only Mode

### What is Cloud-Init Only Mode?

Cloud-Init Only Mode is a new feature that allows you to generate standalone cloud-init configuration files **without processing any ISO**. This mode generates `user-data` and `meta-data` files that can be used with:

- **NoCloud datasource**: Create a config ISO or copy to `/var/lib/cloud/seed/nocloud-net/`
- **HTTP datasource**: Serve files from web server
- **ConfigDrive**: OpenStack and cloud platform deployments
- **Existing systems**: Apply configuration to already-installed Ubuntu systems

### Why Use Cloud-Init Only Mode?

**Speed**: Generates configuration in seconds (no ISO extraction/repacking)

**Flexibility**: Use with any Ubuntu 24.04 installation method:
- Standard Ubuntu ISOs
- Cloud images
- Pre-installed systems
- Docker containers with cloud-init

**Reusability**: Generate configs once, deploy many ways:
- Create NoCloud ISO
- HTTP server deployment
- Copy to existing systems
- Orchestration tools (Ansible, Terraform, etc.)

**Testing**: Iterate on BGP configurations instantly without ISO rebuilds

**Scale**: Perfect for large deployments with orchestration systems

### Command-Line Options (Cloud-Init Only Mode)

| Option | Required | Description |
|--------|----------|-------------|
| `--cloud-init-only` | Yes | Enable cloud-init only mode (no ISO processing) |
| `--output-dir DIR` | Yes | Directory to save cloud-init files |
| `--local-asn ASN` | Yes | Local BGP AS number (1-4294967295) |
| `--router-id IP` | Yes | BGP router ID (IP address format) |
| `--bgp-config FILE` | No | BGP peers configuration file |
| `--bgp-networks LIST` | No | Networks to advertise (CIDR, comma-separated) |
| `--verbose` | No | Enable verbose output |
| `-h, --help` | No | Show help message |

Note: `--iso`, `--output`, and `--work-dir` are **not used** in cloud-init only mode.

### Basic Cloud-Init Only Usage

```bash
# Generate cloud-init files
sudo ./stage2-network.sh \
  --cloud-init-only \
  --output-dir /tmp/bgp-config \
  --local-asn 65001 \
  --router-id 10.0.0.1

# Result: Creates two files
# /tmp/bgp-config/user-data
# /tmp/bgp-config/meta-data
```

### Cloud-Init Only with BGP Configuration

```bash
# Create BGP peers file
cat > dc1-peers.conf << EOF
65100,10.1.1.1,10.1.1.2
65101,10.1.2.1,10.1.2.2
EOF

# Generate cloud-init with full BGP config
sudo ./stage2-network.sh \
  --cloud-init-only \
  --output-dir dc1-cloud-init \
  --local-asn 65001 \
  --router-id 10.1.0.1 \
  --bgp-config dc1-peers.conf \
  --bgp-networks "10.1.0.0/16,172.16.1.0/24"
```

### Deployment Methods

#### Method 1: Create NoCloud ISO

Use `cloud-localds` (part of cloud-utils package) to create a config ISO:

```bash
# Generate cloud-init files
sudo ./stage2-network.sh \
  --cloud-init-only \
  --output-dir /tmp/dc1-config \
  --local-asn 65001 \
  --router-id 10.1.0.1 \
  --bgp-config dc1-peers.conf

# Create NoCloud ISO
cloud-localds dc1-config.iso /tmp/dc1-config/user-data /tmp/dc1-config/meta-data

# Boot Ubuntu with two ISOs:
# 1. Ubuntu installation ISO
# 2. dc1-config.iso (cloud-init configuration)
```

**Use Case**: VM deployments, testing environments

#### Method 2: Copy to Existing System

Apply configuration to an already-installed Ubuntu 24.04 system:

```bash
# Generate cloud-init files
sudo ./stage2-network.sh \
  --cloud-init-only \
  --output-dir /tmp/bgp-config \
  --local-asn 65001 \
  --router-id 10.2.0.1 \
  --bgp-config dc2-peers.conf

# Copy to target system's NoCloud directory
sudo mkdir -p /var/lib/cloud/seed/nocloud-net/
sudo cp /tmp/bgp-config/user-data /var/lib/cloud/seed/nocloud-net/
sudo cp /tmp/bgp-config/meta-data /var/lib/cloud/seed/nocloud-net/

# Reset and run cloud-init
sudo cloud-init clean
sudo cloud-init init
sudo cloud-init modules --mode=config
sudo cloud-init modules --mode=final

# Or simply reboot
sudo reboot
```

**Use Case**: Updating existing systems, post-installation configuration

#### Method 3: HTTP Datasource

Serve cloud-init files from a web server:

```bash
# Generate files
sudo ./stage2-network.sh \
  --cloud-init-only \
  --output-dir /var/www/html/cloud-init/dc1 \
  --local-asn 65001 \
  --router-id 10.1.0.1 \
  --bgp-config dc1-peers.conf

# Ensure web server is running (nginx, apache, python http.server, etc.)
# Files will be available at:
# http://your-server/cloud-init/dc1/user-data
# http://your-server/cloud-init/dc1/meta-data

# Boot Ubuntu with kernel parameter:
# ds=nocloud-net;s=http://your-server/cloud-init/dc1/

# Or configure in grub/boot options
```

**Use Case**: Large-scale deployments, PXE boot, automated provisioning

#### Method 4: ConfigDrive (OpenStack/Cloud)

```bash
# Generate cloud-init files
sudo ./stage2-network.sh \
  --cloud-init-only \
  --output-dir /tmp/configdrive \
  --local-asn 65001 \
  --router-id 10.3.0.1 \
  --bgp-config cloud-peers.conf

# Create ConfigDrive structure
mkdir -p /tmp/configdrive/openstack/latest/
cp /tmp/configdrive/user-data /tmp/configdrive/openstack/latest/user_data
cp /tmp/configdrive/meta-data /tmp/configdrive/openstack/latest/meta_data.json

# Create ConfigDrive ISO
genisoimage -o configdrive.iso -V config-2 -r -J /tmp/configdrive

# Attach to OpenStack instance or cloud VM
```

**Use Case**: OpenStack, cloud platforms, infrastructure-as-code

### Cloud-Init Only Mode Examples

#### Example 1: Multiple Datacenters (Quick Configuration)

```bash
# Generate configs for 3 datacenters in seconds
sudo ./stage2-network.sh --cloud-init-only --output-dir dc1-config \
  --local-asn 65001 --router-id 10.1.0.1 --bgp-config dc1-peers.conf

sudo ./stage2-network.sh --cloud-init-only --output-dir dc2-config \
  --local-asn 65002 --router-id 10.2.0.1 --bgp-config dc2-peers.conf

sudo ./stage2-network.sh --cloud-init-only --output-dir dc3-config \
  --local-asn 65003 --router-id 10.3.0.1 --bgp-config dc3-peers.conf

# Create NoCloud ISOs
cloud-localds dc1-config.iso dc1-config/user-data dc1-config/meta-data
cloud-localds dc2-config.iso dc2-config/user-data dc2-config/meta-data
cloud-localds dc3-config.iso dc3-config/user-data dc3-config/meta-data
```

#### Example 2: Testing BGP Configurations

```bash
# Test different ASN configurations quickly
for asn in 65001 65002 65003; do
  sudo ./stage2-network.sh \
    --cloud-init-only \
    --output-dir test-asn-${asn} \
    --local-asn ${asn} \
    --router-id 192.168.${asn#650}.1 \
    --bgp-config test-peers.conf
done

# Each iteration takes seconds!
```

#### Example 3: HTTP-Based Mass Deployment

```bash
# Set up web server directory structure
WEB_ROOT=/var/www/html/cloud-init

# Generate configs for 100 servers
for i in {1..100}; do
  sudo ./stage2-network.sh \
    --cloud-init-only \
    --output-dir ${WEB_ROOT}/server-${i} \
    --local-asn $((65000 + i)) \
    --router-id 10.0.$((i / 256)).$((i % 256)) \
    --bgp-config server-${i}-peers.conf \
    --bgp-networks "10.${i}.0.0/24"
done

# Each server boots with: ds=nocloud-net;s=http://provisioner/cloud-init/server-N/
```

#### Example 4: Integration with Ansible/Terraform

```bash
# Generate cloud-init as part of infrastructure provisioning

# In Terraform:
resource "null_resource" "generate_cloud_init" {
  provisioner "local-exec" {
    command = <<EOF
sudo ./stage2-network.sh \
  --cloud-init-only \
  --output-dir ${path.module}/cloud-init/${var.datacenter} \
  --local-asn ${var.bgp_asn} \
  --router-id ${var.router_id} \
  --bgp-config ${var.bgp_peers_file}
EOF
  }
}

# Use generated files in OpenStack, AWS user-data, etc.
```

### What's in the Generated Files?

**user-data** (Cloud-Init YAML):
```yaml
#cloud-config

# Embedded configuration files
write_files:
  - path: /etc/frr-bgp-config/local-asn
  - path: /etc/frr-bgp-config/router-id
  - path: /etc/frr-bgp-config/bgp-peers.conf
  - path: /etc/frr-bgp-config/bgp-networks
  - path: /usr/local/bin/detect-mellanox.sh  # Complete script embedded
  - path: /usr/local/bin/configure-bgp.sh    # Complete script embedded

# Execution commands
runcmd:
  - /usr/local/bin/detect-mellanox.sh
  - /usr/local/bin/configure-bgp.sh
  - systemctl enable frr
  - systemctl start frr
```

**meta-data** (Cloud-Init metadata):
```yaml
instance-id: bgp-router-<timestamp>
local-hostname: bgp-router
```

### Debugging Cloud-Init Deployments

After deploying with cloud-init:

```bash
# Check cloud-init status
cloud-init status
cloud-init status --long

# View cloud-init logs
cat /var/log/cloud-init.log
cat /var/log/cloud-init-output.log

# View network setup logs
cat /var/log/network-setup.log
cat /var/log/mellanox-detect.log
cat /var/log/bgp-configure.log

# Check which datasource was used
cloud-init query datasource

# View final user-data
cloud-init query userdata

# Analyze timing
cloud-init analyze show
cloud-init analyze blame

# Re-run cloud-init (for testing)
sudo cloud-init clean
sudo cloud-init init
sudo cloud-init modules --mode=config
sudo cloud-init modules --mode=final
```

### Cloud-Init Only vs ISO Mode Comparison

| Feature | Cloud-Init Only | ISO Mode |
|---------|----------------|----------|
| **Speed** | ⚡ Seconds | ⏱️ Minutes |
| **ISO Required** | ❌ No | ✅ Yes |
| **Disk Space** | ✅ Minimal (KB) | ❌ Large (GB) |
| **Use with existing systems** | ✅ Yes | ❌ No |
| **HTTP deployment** | ✅ Yes | ❌ No |
| **Iteration speed** | ⚡ Instant | ⏱️ Slow |
| **Best for** | Automation, testing, existing systems | New installations, standardization |
| **Deployment methods** | Many | Boot from ISO |
| **Learning curve** | ⚠️ Requires cloud-init knowledge | ✅ Simple |

### When to Use Cloud-Init Only Mode

✅ **Use Cloud-Init Only when**:
- Deploying to existing Ubuntu installations
- Using orchestration tools (Ansible, Terraform)
- Need HTTP-based deployment
- Testing BGP configurations rapidly
- Large-scale automated deployments
- Using cloud platforms (OpenStack, AWS, etc.)
- Want maximum deployment flexibility

❌ **Use ISO Mode instead when**:
- Creating standardized installation media
- New bare-metal installations
- Need everything embedded in one file
- Simpler deployment process preferred
- Limited cloud-init infrastructure

## Advanced Configuration

### Command Line Options

| Option | Required | Description |
|--------|----------|-------------|
| `--iso FILE` | Yes | Path to Ubuntu 24.04 ISO file |
| `--output FILE` | Yes | Path for output ISO file |
| `--local-asn ASN` | Yes | Local ASN number (1-4294967295) |
| `--router-id IP` | Yes | BGP router ID (IP address format) |
| `--packages LIST` | No | Comma-separated additional packages |
| `--bgp-config FILE` | No | BGP peers configuration file |
| `--bgp-networks LIST` | No | Networks to advertise (CIDR, comma-separated) |
| `--work-dir DIR` | No | Custom working directory |
| `--verbose` | No | Enable verbose output |
| `-h, --help` | No | Show help message |

### Working Directory

By default, the script uses `/tmp/os-repack-$$` as the working directory. You can specify a custom location:

```bash
sudo ./repack-os.sh \
  --iso ubuntu.iso \
  --output custom.iso \
  --local-asn 65001 \
  --work-dir /mnt/large-disk/repack-work
```

## BGP Configuration

### Configuration File Format

Create a BGP peers configuration file with the following format:

```
# Format: remote_asn,remote_ip,local_ip
# Lines starting with # are comments
# Peers are automatically assigned to Mellanox interfaces in detection order
65002,192.168.1.1,192.168.1.2
65003,192.168.2.1,192.168.2.2
65100,10.0.1.1,10.0.1.2
```

Each line contains:
1. **remote_asn**: Remote peer ASN number
2. **remote_ip**: Remote peer IP address
3. **local_ip**: Local IP address for this peering connection

**Important**: 
- You do NOT specify interface names
- Peers are automatically assigned to detected Mellanox interfaces in order:
  - First peer → First Mellanox interface
  - Second peer → Second Mellanox interface
  - And so on...
- If you have more peers than Mellanox interfaces, extra peers will be skipped with a warning

### Example BGP Configuration

```bash
# Create BGP configuration file
cat > bgp-peers.conf << EOF
# Production BGP peers (auto-assigned to Mellanox interfaces)
65100,10.0.1.1,10.0.1.2
65200,10.0.2.1,10.0.2.2
65300,10.0.3.1,10.0.3.2
EOF

# Repack ISO with BGP configuration
sudo ./repack-os.sh \
  --iso ubuntu-24.04.iso \
  --output bgp-ubuntu.iso \
  --local-asn 65001 \
  --router-id 10.0.0.1 \
  --bgp-config bgp-peers.conf
```

### BGP Network Advertisement

**IMPORTANT**: By default, NO networks are advertised. You must explicitly specify networks to advertise using the `--bgp-networks` parameter.

```bash
# Advertise specific networks (comma-separated, CIDR notation)
sudo ./repack-os.sh \
  --iso ubuntu-24.04.iso \
  --output custom.iso \
  --local-asn 65001 \
  --router-id 10.0.0.1 \
  --bgp-config bgp-peers.conf \
  --bgp-networks "10.0.0.0/24,192.168.1.0/24,172.16.0.0/16"
```

**How It Works:**
- Networks specified with `--bgp-networks` are advertised to ALL BGP peers
- Networks must be in CIDR notation (e.g., 10.0.0.0/24)
- Multiple networks are comma-separated
- These networks are embedded in the ISO and configured during first boot

**Example Use Cases:**
```bash
# Advertise a single /24 network
--bgp-networks "10.0.0.0/24"

# Advertise multiple networks
--bgp-networks "10.0.0.0/24,10.0.1.0/24,10.0.2.0/24"

# Advertise larger subnets
--bgp-networks "172.16.0.0/16,192.168.0.0/16"
```

### How BGP Configuration Works

1. **During Repacking**: BGP configuration (peers and networks) is embedded into the ISO
2. **First Boot**: 
   - Mellanox interfaces are detected automatically
   - BGP is configured only for Mellanox interfaces
   - Specified networks are advertised to all peers
   - FRR service is started with the configuration
3. **Ongoing**: BGP sessions are maintained and monitored

### Verifying BGP on Deployed System

After booting from the repacked ISO:

```bash
# Check Mellanox interfaces detected
cat /etc/mellanox-interfaces.conf

# View BGP configuration
sudo cat /etc/frr/frr.conf

# Check BGP status
sudo vtysh -c "show ip bgp summary"

# View BGP neighbors
sudo vtysh -c "show ip bgp neighbors"

# View advertised networks
sudo vtysh -c "show ip bgp"

# Check specific network advertisement
sudo vtysh -c "show ip bgp 10.0.0.0/24"

# Check systemd services
systemctl status mellanox-detect.service
systemctl status bgp-configure.service
systemctl status frr.service
```

## Troubleshooting

### Issue: Insufficient Disk Space

**Symptoms**: Script fails with "No space left on device"

**Solution**:
```bash
# Check available space
df -h /tmp

# Use custom work directory on larger disk
sudo ./repack-os.sh \
  --iso ubuntu.iso \
  --output custom.iso \
  --local-asn 65001 \
  --router-id 1.1.1.1 \
  --work-dir /mnt/large-disk/work
```

### Issue: Missing Dependencies

**Symptoms**: "Missing required dependencies" error

**Solution**:
```bash
# Re-run dependency installer
sudo ./install-deps.sh

# Verify installation manually
which xorriso unsquashfs mksquashfs genisoimage
```

### Issue: Invalid ISO File

**Symptoms**: "File is not a valid ISO image"

**Solution**:
- Verify the ISO file is not corrupted:
```bash
# Check file type
file ubuntu-24.04.iso

# Verify MD5/SHA256 checksum (compare with official Ubuntu checksums)
sha256sum ubuntu-24.04.iso
```

### Issue: BGP Not Configured

**Symptoms**: BGP peers not established after boot

**Solution**:
1. Check if Mellanox interfaces were detected:
```bash
cat /etc/mellanox-interfaces.conf
```

2. Check systemd service logs:
```bash
sudo journalctl -u mellanox-detect.service
sudo journalctl -u bgp-configure.service
sudo journalctl -u frr.service
```

3. Verify FRR configuration:
```bash
sudo cat /etc/frr/frr.conf
```

4. Check if interfaces are actually Mellanox devices:
```bash
lspci | grep -i mellanox
```

### Issue: Package Installation Failed

**Symptoms**: Specific packages fail to install

**Solution**:
- Check package names are correct for Ubuntu 24.04
- Verify network connectivity during repacking
- Check `/var/log/apt/` logs in the chroot environment

## Examples

### Example 1: Minimal Custom ISO

```bash
sudo ./repack-os.sh \
  --iso /path/to/ubuntu-24.04-server-amd64.iso \
  --output /path/to/custom-ubuntu.iso \
  --local-asn 65001 \
  --router-id 1.1.1.1
```
```bash
sudo ./repack-os.sh \
  --iso ubuntu-24.04-server-amd64.iso \
  --output minimal-custom.iso \
  --local-asn 65001 \
  --router-id 1.1.1.1
```

### Example 2: Development Server ISO

```bash
sudo ./repack-os.sh \
  --iso /path/to/ubuntu-24.04.iso \
  --output /path/to/custom.iso \
  --local-asn 65001 \
  --router-id 10.0.0.1 \
  --packages "vim,htop,iperf3,tcpdump,stress-ng"
```
```bash
sudo ./repack-os.sh \
  --iso ubuntu-24.04-server-amd64.iso \
  --output dev-server.iso \
  --local-asn 65001 \
  --router-id 10.0.0.1 \
  --packages "docker.io,docker-compose,git,vim,tmux,build-essential,python3-pip"
```

### Example 3: Network Infrastructure ISO

```bash
# Create BGP configuration (auto-assigned to Mellanox interfaces)
cat > network-bgp.conf << EOF
65100,10.0.1.1,10.0.1.2
65200,10.0.2.1,10.0.2.2
65300,10.0.3.1,10.0.3.2
65400,10.0.4.1,10.0.4.2
EOF

sudo ./repack-os.sh \
  --iso ubuntu-24.04-server-amd64.iso \
  --output network-infra.iso \
  --local-asn 65001 \
  --bgp-config network-bgp.conf \
  --packages "wireshark,tcpdump,iperf3,mtr,nmap,snmp"
```

### Example 4: OpenStack Compute Node

```bash
sudo ./repack-os.sh \
  --iso ubuntu.iso \
  --output custom.iso \
  --local-asn 65001 \
  --router-id 192.168.1.1 \
  --work-dir /mnt/large-disk/repack-work
```
```bash
sudo ./repack-os.sh \
  --iso ubuntu-24.04-server-amd64.iso \
  --output openstack-compute.iso \
  --local-asn 65001 \
  --router-id 10.10.10.1 \
  --packages "ceph-common,lvm2,thin-provisioning-tools"
```

### Example 5: Custom Work Directory

```bash
# Use SSD for faster processing
sudo ./repack-os.sh \
  --iso ubuntu-24.04-server-amd64.iso \
  --output network-infra.iso \
  --local-asn 65001 \
  --router-id 192.168.1.1 \
  --bgp-config network-bgp.conf \
  --packages "wireshark,tcpdump,iperf3,mtr,nmap,snmp"
```

## Default Packages

The following packages are installed by default in all repacked ISOs:

### Network Tools
- net-tools (ifconfig, netstat)
- iproute2 (ip command)
- ethtool
- bridge-utils
- vlan
- ifupdown

### FRR Routing
- frr (BGP, OSPF, etc.)
- frr-pythontools

### Debugging Tools
- tcpdump, tshark
- strace, ltrace
- sysstat (sar, iostat, mpstat)
- htop, iotop
- lsof, netcat
- traceroute, mtr
- curl, wget
- vim, nano
- dnsutils, iputils-ping
- snmp tools

### OpenStack
- python3-openstackclient
- Various OpenStack client libraries
- qemu-kvm, libvirt
- openvswitch-switch

### Development
- build-essential
- git
- python3-pip
- python3-dev

### System Utilities
- screen, tmux
- rsync, tar, gzip
- compression tools

## Post-Installation

After deploying the customized ISO:

1. **Verify Mellanox Interfaces**:
```bash
# Use SSD for faster processing
sudo ./repack-os.sh \
  --iso ubuntu-24.04.iso \
  --output custom.iso \
  --local-asn 65001 \
  --router-id 172.16.0.1 \
  --work-dir /mnt/ssd/repack-work \
  --verbose
```

3. **Monitor Services**:
```bash
systemctl status frr
systemctl status openvswitch-switch
```

4. **View Logs**:
```bash
sudo journalctl -u bgp-configure.service
sudo tail -f /var/log/frr/frr.log
```

## Best Practices

1. **Disk Space**: Always ensure you have at least 20GB free space
2. **ISO Verification**: Verify the source ISO checksum before repacking
3. **Testing**: Test the repacked ISO in a VM before production deployment
4. **BGP Configuration**: Double-check BGP peer configurations for typos
5. **Package Selection**: Only include necessary packages to keep ISO size manageable
6. **Backup**: Keep the original ISO file as backup
7. **Documentation**: Document your custom package selections and BGP configurations

## Performance Tips

1. **Use SSD**: Store working directory on SSD for faster processing
2. **Disable Antivirus**: Temporarily disable antivirus during repacking
3. **Close Applications**: Close unnecessary applications to free up RAM
4. **Network Connection**: Ensure stable internet for package downloads

## Security Considerations

1. The repacked ISO contains the same base security as Ubuntu 24.04
2. Additional packages should be from trusted repositories
3. BGP configurations are stored in plaintext in the ISO
4. Consider encryption for sensitive deployments
5. Update packages after deployment for latest security patches
