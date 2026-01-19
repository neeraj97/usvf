# Virtual DC Cleanup Guide

Complete guide for managing and destroying Virtual DC resources.

## Quick Reference

```bash
# List all resources
./scripts/deploy-virtual-dc.sh --list

# Stop all VMs (keeps everything, just stops VMs)
./scripts/deploy-virtual-dc.sh --stop

# Start all VMs
./scripts/deploy-virtual-dc.sh --start

# Destroy everything (with confirmation)
./scripts/deploy-virtual-dc.sh --destroy

# Destroy without confirmation (use with caution!)
./scripts/deploy-virtual-dc.sh --destroy-force

# Destroy but keep Ubuntu 24.04 base image
./scripts/deploy-virtual-dc.sh --destroy --keep-base-images
```

## What Gets Destroyed

### Complete Cleanup (`--destroy`)

When you run `./scripts/deploy-virtual-dc.sh --destroy`, the following happens:

1. **⚠️ Confirmation Prompt**
   ```
   WARNING: This will destroy all Virtual DC resources!
   Are you sure you want to destroy ALL resources? (type 'yes' to confirm):
   ```

2. **VM Destruction**
   - All hypervisor VMs are stopped and destroyed
   - All switch VMs are stopped and destroyed
   - VM definitions are removed from libvirt
   - Status: `virsh list --all` shows no VMs

3. **Network Cleanup**
   - Management networks destroyed
   - Data plane networks destroyed
   - All virtual bridges removed
   - Status: `virsh net-list --all` shows no virtual-dc networks

4. **Disk Image Removal**
   - All VM QCOW2 disk images deleted
   - Directory: `config/disks/*.qcow2`
   - Base image kept by default (unless `--destroy-force` used without `--keep-base-images`)

5. **Configuration Cleanup**
   - Cloud-init ISOs removed
   - BGP configuration files deleted
   - Verification reports removed
   - Directories cleaned but preserved

6. **SSH Keys (Optional)**
   ```
   Remove SSH keys for virtual-dc-lab? (y/N):
   ```
   - If 'y': SSH keys deleted
   - If 'N': Keys preserved for future use

## Resource Protection

### What's NEVER Destroyed Automatically

1. **Base Ubuntu 24.04 Image**
   - Location: `images/ubuntu-24.04-server-cloudimg-amd64.img`
   - Size: ~700MB
   - Reason: Expensive to re-download
   - Override: Use `--destroy` without `--keep-base-images` flag

2. **Configuration Files**
   - `config/topology.yaml` - Your topology design
   - `config/*.example` - Example configurations
   - Custom configurations in `examples/`

3. **Project Code**
   - All shell scripts
   - Module files
   - Documentation

## Cleanup Scenarios

### Scenario 1: Testing Different Topologies

**Situation**: You want to destroy current deployment and try a different topology.

```bash
# Destroy current deployment (keep base image)
./scripts/deploy-virtual-dc.sh --destroy --keep-base-images

# Edit topology
vim config/topology.yaml

# Deploy new topology
./scripts/deploy-virtual-dc.sh
```

**Time Saved**: No need to re-download Ubuntu 24.04 image (~5-10 minutes)

### Scenario 2: Freeing Disk Space

**Situation**: You need to free up disk space but keep your configuration.

```bash
# Destroy everything including VM disks
./scripts/deploy-virtual-dc.sh --destroy

# Configuration files remain intact
ls config/topology.yaml  # Still there!
```

**Space Freed**: 
- VM disks: ~2GB per hypervisor
- Cloud-init ISOs: ~1MB per VM
- Total: Typically 10-20GB for 4-8 hypervisors

### Scenario 3: Temporary Shutdown

**Situation**: You need to free RAM but plan to resume work later.

```bash
# Just stop VMs (no destruction)
./scripts/deploy-virtual-dc.sh --stop

# Later, resume work
./scripts/deploy-virtual-dc.sh --start
```

**RAM Freed**: Typically 4-8GB depending on hypervisor count

### Scenario 4: Complete Removal

**Situation**: Completely remove Virtual DC including base image.

```bash
# Destroy everything
./scripts/deploy-virtual-dc.sh --destroy-force

# Manually remove base image if needed
rm -rf images/ubuntu-24.04-*.img

# Manually remove SSH keys if desired
rm -f config/*-ssh-key*
```

## Safety Features

### 1. Confirmation Prompts

**First Prompt** (for `--destroy`):
```
Are you sure you want to destroy ALL resources? (type 'yes' to confirm):
```
- Must type exactly 'yes' (not 'y')
- Any other input cancels operation

**Second Prompt** (for SSH keys):
```
Remove SSH keys for virtual-dc-lab? (y/N):
```
- Default is 'N' (keep keys)
- Keys are useful for future deployments

### 2. Force Mode Safety

When using `--destroy-force`:
- ⚠️ **No confirmation prompts**
- ⚠️ **Immediate destruction**
- ⚠️ **Use only in scripts or when certain**

Example safe usage:
```bash
# In automated CI/CD pipeline
./scripts/deploy-virtual-dc.sh --destroy-force --keep-base-images
```

### 3. Resource Listing

Before destroying, always check what you have:

```bash
./scripts/deploy-virtual-dc.sh --list
```

Output shows:
```
Virtual DC Resources for: virtual-dc-lab
═══════════════════════════════════════════════════════

Virtual Machines:
 Id   Name            State
--------------------------------
 1    hypervisor-1    running
 2    hypervisor-2    running
 -    leaf-1          shut off
 -    leaf-2          shut off

Virtual Networks:
 Name                 State    Autostart   Persistent
--------------------------------------------------------
 virtual-dc-lab-mgmt  active   yes         yes

Disk Images:
50G     config/disks/hypervisor-1.qcow2
50G     config/disks/hypervisor-2.qcow2

Cloud-init ISOs:
1.0M    config/cloud-init/hypervisor-1-cidata.iso
1.0M    config/cloud-init/hypervisor-2-cidata.iso
═══════════════════════════════════════════════════════
```

## Verification After Cleanup

### Check VMs Removed

```bash
virsh list --all
# Should show no virtual-dc related VMs
```

### Check Networks Removed

```bash
virsh net-list --all
# Should show no virtual-dc networks
```

### Check Disk Space Freed

```bash
# Before cleanup
du -sh config/disks/
# Output: 20G    config/disks/

# After cleanup
du -sh config/disks/
# Output: 0       config/disks/
```

### Verify Configuration Preserved

```bash
# Your topology should still exist
cat config/topology.yaml

# SSH keys (if you chose to keep them)
ls -lh config/*-ssh-key*
```

## Common Issues

### Issue 1: VMs Won't Stop

**Problem**: VMs stuck in "shutting down" state

**Solution**:
```bash
# Force destroy individual VM
virsh destroy hypervisor-1

# Then run cleanup again
./scripts/deploy-virtual-dc.sh --destroy
```

### Issue 2: Networks Won't Delete

**Problem**: Error "network is still in use"

**Solution**:
```bash
# Ensure all VMs are destroyed first
virsh list --all

# Manually destroy network
virsh net-destroy virtual-dc-lab-mgmt
virsh net-undefine virtual-dc-lab-mgmt
```

### Issue 3: Permission Denied

**Problem**: Cannot delete disk images

**Solution**:
```bash
# Check file ownership
ls -lh config/disks/

# Fix permissions if needed
sudo chown -R $USER:$USER config/disks/
sudo rm -rf config/disks/*.qcow2
```

## Best Practices

### 1. Always List Before Destroying

```bash
# See what you have
./scripts/deploy-virtual-dc.sh --list

# Then decide what to do
./scripts/deploy-virtual-dc.sh --destroy
```

### 2. Keep Base Images

```bash
# Saves bandwidth on next deployment
./scripts/deploy-virtual-dc.sh --destroy --keep-base-images
```

### 3. Backup Configuration First

```bash
# Before major cleanup
cp config/topology.yaml config/topology.yaml.backup

# Then destroy
./scripts/deploy-virtual-dc.sh --destroy
```

### 4. Use Stop Instead of Destroy for Testing

```bash
# If you're just testing something temporarily
./scripts/deploy-virtual-dc.sh --stop

# Make your changes

# Resume testing
./scripts/deploy-virtual-dc.sh --start
```

### 5. Preserve SSH Keys

- Keep SSH keys between deployments
- Allows consistent access across rebuilds
- Useful for automation scripts

## Automation Examples

### Nightly Cleanup Script

```bash
#!/bin/bash
# cleanup-nightly.sh

# Destroy old deployment
/path/to/deploy-virtual-dc.sh --destroy-force --keep-base-images

# Deploy fresh environment
/path/to/deploy-virtual-dc.sh

# Run tests
./run-tests.sh
```

### Conditional Cleanup

```bash
#!/bin/bash
# cleanup-if-needed.sh

# Get current disk usage
usage=$(df /home | tail -1 | awk '{print $5}' | sed 's/%//')

# If > 80% full, cleanup
if [ $usage -gt 80 ]; then
    echo "Disk usage high ($usage%), cleaning up..."
    ./scripts/deploy-virtual-dc.sh --destroy-force
fi
```

## Recovery

### Accidentally Destroyed Everything?

Don't panic! Your configuration is safe:

1. **Configuration intact**: `config/topology.yaml`
2. **Scripts intact**: All deployment scripts preserved
3. **Re-deploy quickly**:
   ```bash
   # If base image preserved
   ./scripts/deploy-virtual-dc.sh  # 5-10 minutes
   
   # If base image deleted
   ./scripts/deploy-virtual-dc.sh --check-prereqs  # Downloads image
   ./scripts/deploy-virtual-dc.sh  # Then deploy
   ```

## Summary

| Command | VMs | Networks | Disks | Configs | Base Image | SSH Keys |
|---------|-----|----------|-------|---------|------------|----------|
| `--stop` | Stop | Keep | Keep | Keep | Keep | Keep |
| `--destroy` | Delete | Delete | Delete | Delete | Keep | Ask |
| `--destroy-force` | Delete | Delete | Delete | Delete | Keep | Delete |
| `--destroy` + `--keep-base-images` | Delete | Delete | Delete | Delete | **Keep** | Ask |

**Recommended**: Always use `--destroy --keep-base-images` unless you specifically need to remove the base image.
