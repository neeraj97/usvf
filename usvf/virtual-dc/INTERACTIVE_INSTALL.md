# Interactive Installation Guide

## Overview

The Virtual DC deployment system now features **interactive installation** that prompts users to install missing prerequisites during deployment.

## How It Works

### Automatic Prerequisites Check

When you run the full deployment, the system automatically checks for missing tools in **Step 2**:

```bash
cd usvf/virtual-dc

# Full deployment - prerequisites checked automatically
./scripts/deploy-virtual-dc.sh
```

**Deployment Flow:**
```
Step 1: Validating Configuration ✓
Step 2: Checking Prerequisites    ← Interactive prompts happen here
Step 3: Creating Management Network
Step 4: Deploying Hypervisors
Step 5: Deploying SONiC Switches
Step 6: Configuring Virtual Cabling
Step 7: Configuring BGP
Step 8: Verifying Deployment
```

### Interactive Installation Example

When the system finds a missing tool, it prompts you:

```
═══════════════════════════════════════════════════════
  Checking Required Tools
═══════════════════════════════════════════════════════

✓ YAML parser (yq) yq version 4.35.1
✗ JSON processor (jq) is not installed

  Would you like to install JSON processor now? (y/N): y
  Installing JSON processor...
  Updating package cache...
  ✓ Installation completed
✓ JSON processor installed successfully

✓ KVM management (virsh) 
✗ VM installation (virt-install) is not installed

  Would you like to install VM installation now? (y/N): y
  Installing VM installation...
  ✓ Installation completed
  Adding user to libvirt and kvm groups...
  Note: You may need to log out and back in for group changes to take effect
✓ VM installation installed successfully

✗ Disk image management (qemu-img) is not installed

  Would you like to install Disk image management now? (y/N): n
  Skipping Disk image management installation

Error: Missing required tools. Please install them and try again.
```

## Usage Modes

### 1. Interactive Mode (Default)

Prompts for each missing tool:

```bash
./scripts/deploy-virtual-dc.sh
```

**or**

```bash
INTERACTIVE_INSTALL=true ./scripts/deploy-virtual-dc.sh
```

### 2. Non-Interactive Mode

Only reports missing tools without prompting:

```bash
INTERACTIVE_INSTALL=false ./scripts/deploy-virtual-dc.sh
```

**Output in non-interactive mode:**
```
✗ JSON processor (jq) is not installed
  Install with: 
    sudo apt install -y jq
```

### 3. Check Prerequisites Only

Check and install prerequisites without deploying:

```bash
./scripts/deploy-virtual-dc.sh --check-prereqs
```

## Tools Checked

The system checks for 13 essential tools:

| Tool | Description | Installation |
|------|-------------|--------------|
| yq | YAML parser | Downloaded from GitHub |
| jq | JSON processor | `apt install jq` |
| virsh | KVM management | `apt install libvirt-daemon-system libvirt-clients` |
| virt-install | VM installation | `apt install virtinst` |
| qemu-img | Disk image management | `apt install qemu-kvm qemu-utils` |
| wget | File download | `apt install wget` |
| curl | File download | `apt install curl` |
| ip | Network configuration | `apt install iproute2` |
| ssh | SSH client | `apt install openssh-client` |
| ssh-keygen | SSH key generation | `apt install openssh-client` |
| genisoimage | ISO creation | `apt install genisoimage` |
| cloud-localds | Cloud-init | `apt install cloud-image-utils` |
| mkpasswd | Password hashing | `apt install whois` |

## System Checks

Beyond tools, the system also verifies:

✅ **Hardware Virtualization** - Checks for Intel VT-x or AMD-V support  
✅ **libvirt Daemon** - Prompts to start if not running  
✅ **Disk Space** - Warns if less than 100GB available  
✅ **Network Configuration** - Checks libvirt default network  
✅ **Ubuntu 24.04 Image** - Downloads if not present (~700MB)  

## Special Features

### Smart Package Cache Management

```bash
# Only updates apt cache if older than 24 hours
apt_cache_age=$(( ($(date +%s) - $(stat -c %Y /var/cache/apt/pkgcache.bin)) / 3600 ))
if [[ $apt_cache_age -gt 24 ]]; then
    log_info "Updating package cache..."
    sudo apt-get update -qq
fi
```

### Automatic Service Configuration

When installing libvirt packages:
- Adds user to `libvirt` and `kvm` groups
- Enables `libvirtd` service
- Starts `libvirtd` service
- Warns user to log out and back in

### libvirt Daemon Startup

If libvirt daemon is not running:

```
✗ libvirt daemon is not running or not accessible

Would you like to start the libvirt daemon? (y/N): y
Starting libvirt daemon...
✓ libvirt daemon started successfully
```

## Error Handling

### Fixed Issues

1. **Unbound Variable Error** - Fixed `$4` parameter issue:
   ```bash
   # Before (caused error):
   local install_packages="$4"
   
   # After (fixed):
   local install_packages="${4:-}"  # Optional with default empty value
   ```

2. **Prerequisites in Full Deployment** - Already integrated in Step 2

## Common Scenarios

### Scenario 1: Fresh Ubuntu Installation

```bash
# User has fresh Ubuntu 24.04, nothing installed
cd usvf/virtual-dc
./scripts/deploy-virtual-dc.sh

# System prompts for each missing tool
# User answers 'y' to each
# Installation happens automatically
# Deployment proceeds
```

### Scenario 2: Partial Installation

```bash
# User has some tools but not all
cd usvf/virtual-dc
./scripts/deploy-virtual-dc.sh

# System only prompts for missing tools
# Skips tools that are already installed
# User can selectively install
```

### Scenario 3: CI/CD Pipeline

```bash
# Automated deployment - no interaction wanted
export INTERACTIVE_INSTALL=false
./scripts/deploy-virtual-dc.sh

# System reports missing tools
# Exits with error if tools missing
# Script can install manually first
```

### Scenario 4: Just Check Prerequisites

```bash
# User wants to prepare system first
./scripts/deploy-virtual-dc.sh --check-prereqs

# Installs all missing tools
# Downloads Ubuntu 24.04 image
# Exits without deploying
```

## Tips for Best Experience

### First-Time Users

1. **Use interactive mode** - Let the system guide you
2. **Answer 'y' to all prompts** - Install everything needed
3. **Log out and back in** - After libvirt installation for group changes
4. **Run again** - Prerequisites will pass, deployment proceeds

### Advanced Users

1. **Check first** - Run `--check-prereqs` before deployment
2. **Manual install** - Install packages manually if preferred
3. **Non-interactive** - Use `INTERACTIVE_INSTALL=false` in scripts
4. **Selective install** - Answer 'n' to skip optional tools

### CI/CD Automation

```bash
#!/bin/bash
# CI/CD deployment script

# Install prerequisites non-interactively
sudo apt-get update
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients \
    virtinst bridge-utils iproute2 jq wget curl \
    cloud-image-utils genisoimage whois

# Install yq
sudo wget -q https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
    -O /usr/local/bin/yq
sudo chmod +x /usr/local/bin/yq

# Deploy without interaction
INTERACTIVE_INSTALL=false ./scripts/deploy-virtual-dc.sh
```

## Troubleshooting

### "You may need to log out and back in"

**Problem:** User groups not active in current session

**Solution:**
```bash
# Option 1: Log out and back in (recommended)
logout

# Option 2: Start new shell with updated groups
newgrp libvirt

# Option 3: Check current groups
groups
# Should show: ... libvirt kvm ...
```

### "libvirt daemon is not running"

**Problem:** Service not started

**Solution:**
```bash
# Manual start
sudo systemctl start libvirtd
sudo systemctl enable libvirtd

# Or answer 'y' when prompted during deployment
```

### "Hardware virtualization is not enabled"

**Problem:** VT-x/AMD-V disabled in BIOS

**Solution:**
1. Reboot computer
2. Enter BIOS/UEFI settings (usually F2, F10, or Del)
3. Find "Virtualization Technology" or "VT-x" or "AMD-V"
4. Enable it
5. Save and exit
6. Run deployment again

### Tools Still Missing After Installation

**Problem:** Installation failed silently

**Solution:**
```bash
# Check if tool exists
which qemu-img

# If not, manually install
sudo apt-get install qemu-kvm qemu-utils

# Verify
qemu-img --version
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `INTERACTIVE_INSTALL` | `true` | Enable/disable interactive prompts |
| `CONFIG_FILE` | `config/topology.yaml` | Path to topology configuration |
| `DEBUG` | unset | Enable debug output if set |

## Examples

### Example 1: Fully Automated First-Time Setup

```bash
#!/bin/bash
cd usvf/virtual-dc

# Check prerequisites with interaction
./scripts/deploy-virtual-dc.sh --check-prereqs
# Answer 'y' to all prompts

# Log out and back in for group changes
echo "Please log out and back in, then run:"
echo "./scripts/deploy-virtual-dc.sh"
```

### Example 2: Silent Installation for Scripts

```bash
#!/bin/bash
set -e

cd usvf/virtual-dc

# Non-interactive check first
if ! INTERACTIVE_INSTALL=false ./scripts/deploy-virtual-dc.sh --check-prereqs 2>/dev/null; then
    echo "Installing prerequisites..."
    sudo apt-get update
    sudo apt-get install -y qemu-kvm libvirt-daemon-system [...]
fi

# Deploy
./scripts/deploy-virtual-dc.sh
```

### Example 3: Custom Interactive Logic

```bash
#!/bin/bash
cd usvf/virtual-dc

# Run with interaction
INTERACTIVE_INSTALL=true ./scripts/deploy-virtual-dc.sh

# If failed, user chose to skip some tools
# Provide help
echo ""
echo "If you skipped tool installation, you can:"
echo "1. Run again and answer 'y' to install"
echo "2. Install manually: sudo apt install <package>"
echo "3. Run: ./scripts/deploy-virtual-dc.sh --check-prereqs"
```

## Summary

The interactive installation feature makes Virtual DC deployment much easier:

✅ **User-Friendly** - Prompts guide new users  
✅ **Flexible** - Can enable/disable interaction  
✅ **Smart** - Only prompts for missing tools  
✅ **Integrated** - Part of full deployment flow  
✅ **Safe** - Confirms before installing anything  
✅ **Informative** - Clear feedback on every action  

---

**Ready to deploy?** Just run `./scripts/deploy-virtual-dc.sh` and follow the prompts! 🚀
