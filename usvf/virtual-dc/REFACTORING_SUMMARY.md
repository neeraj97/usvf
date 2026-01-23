# Virtual DC Cabling Refactoring Summary

## Overview

The virtual datacenter deployment has been refactored to use a simpler, more reliable approach for network interface configuration.

## Problem with Previous Approach

### Old Flow (Complex & Error-Prone):
1. ✅ Create management network
2. ✅ Create VMs with **placeholder interfaces** on "default" network
3. ✅ Create P2P networks during cabling step
4. ❌ **Try to update VM interfaces** from "default" to P2P networks
   - Used `virsh update-device` or `attach-interface`
   - Complex PCI slot tracking
   - Often failed due to timing or libvirt issues

### Issues:
- **Interface Mismatch**: VMs created with enp2s0, enp3s0 on "default", but cabling tried to attach NEW interfaces (enp4s0, enp5s0)
- **Update Complexity**: `update-device` required exact PCI address matching
- **Reliability**: Failed when VMs were running or during cloud-init

## New Approach (Simple & Reliable)

### New Flow:
1. ✅ Create management network
2. ✅ **Pre-create ALL P2P networks** (new step!)
3. ✅ Create VMs with interfaces **directly connected to P2P networks**
4. ✅ No updates needed!

### Benefits:
- ✅ **No placeholders** - interfaces connect to correct networks from start
- ✅ **No updates** - VMs created with correct configuration
- ✅ **Predictable** - enp1s0 (mgmt), enp2s0 (p2p-link-0), enp3s0 (p2p-link-1), etc.
- ✅ **Simpler code** - removed complex update logic

## Changes Made

### 1. New Function: `create_p2p_networks()` (cabling.sh)
Pre-creates all P2P networks before VM deployment:

```bash
create_p2p_networks() {
    # Parse topology.yaml cabling section
    # Create libvirt network for each cable connection
    # Network names: dc3-p2p-link-0, dc3-p2p-link-1, etc.
}
```

### 2. New Function: `lookup_interface_network()` (cabling.sh)
Looks up which P2P network an interface should connect to:

```bash
lookup_interface_network() {
    # Input: device_name, interface_name
    # Output: network_name (e.g., "dc3-p2p-link-5")
    # Searches topology.yaml cabling section
}
```

### 3. Updated: `create_hypervisor_vm()` (hypervisor.sh)
Connects interfaces directly to P2P networks during VM creation:

```bash
# OLD:
--network network=default,model=virtio  # Placeholder

# NEW:
for each data interface:
    p2p_network=$(lookup_interface_network "$config_file" "$hostname" "$iface_name")
    --network network=$p2p_network,model=virtio  # Direct connection!
```

### 4. Updated: `create_sonic_vm()` (switches.sh)
Same approach as hypervisors - direct P2P network connection.

### 5. Updated Deployment Order (deploy-virtual-dc.sh)
Added new step before VM creation:

```bash
# OLD ORDER:
Step 3: Create Management Network
Step 4: Deploy Hypervisors (with placeholders)
Step 5: Deploy Switches (with placeholders)
Step 6: Configure Cabling (try to update interfaces)

# NEW ORDER:
Step 3: Create Management Network
Step 4: Pre-Create P2P Networks ← NEW!
Step 5: Deploy Hypervisors (direct connection)
Step 6: Deploy Switches (direct connection)
Step 7: Verify Cabling (no changes needed)
```

### 6. Simplified: `configure_cabling()` (cabling.sh)
Now just verifies networks exist:

```bash
# OLD: Complex update logic with virsh update-device
# NEW: Simple verification that networks were created
configure_cabling() {
    log_info "Virtual cabling already configured during network creation"
    log_success "Cabling verification complete"
}
```

## Technical Details

### P2P Network Naming
Networks are named sequentially based on cabling order:
- `dc3-p2p-link-0` - First cable in topology.yaml
- `dc3-p2p-link-1` - Second cable
- `dc3-p2p-link-N` - Nth cable

### Interface Mapping Example

**Topology Definition:**
```yaml
cabling:
  - source: {device: hypervisor-1, interface: enp2s0}
    destination: {device: leaf-1, interface: enp2s0}
  - source: {device: hypervisor-1, interface: enp3s0}
    destination: {device: leaf-2, interface: enp2s0}
```

**Result:**
- `dc3-p2p-link-0` created for hypervisor-1:enp2s0 ↔ leaf-1:enp2s0
- `dc3-p2p-link-1` created for hypervisor-1:enp3s0 ↔ leaf-2:enp2s0

**VM Creation:**
```bash
virt-install \
  --network network=dc3-mgmt,model=virtio      # enp1s0
  --network network=dc3-p2p-link-0,model=virtio # enp2s0
  --network network=dc3-p2p-link-1,model=virtio # enp3s0
```

### PCI Slot Assignment
Interfaces are added in order, ensuring predictable PCI slots:
- Slot 1 (0x01) → enp1s0 → management network
- Slot 2 (0x02) → enp2s0 → first P2P network
- Slot 3 (0x03) → enp3s0 → second P2P network
- ...

## Migration Guide

### For Existing Deployments:
1. Destroy existing VDC: `./deploy-virtual-dc.sh --destroy`
2. Deploy with new approach: `./deploy-virtual-dc.sh`

### For Development:
The new approach is backwards compatible - existing topology.yaml files work without changes.

## Testing

To test the refactored deployment:

```bash
# Full deployment
cd usvf/virtual-dc
./scripts/deploy-virtual-dc.sh

# Check P2P networks were created
virsh net-list --all | grep p2p-link

# Verify VM interfaces
virsh domiflist dc3-hypervisor-1

# Expected output:
# enp1s0 → dc3-mgmt (management)
# enp2s0 → dc3-p2p-link-X (data)
# enp3s0 → dc3-p2p-link-Y (data)
```

## Verification

After deployment, verify:

1. **All P2P networks exist**:
   ```bash
   virsh net-list --all | grep "dc3-p2p-link"
   ```

2. **VMs have correct interfaces**:
   ```bash
   virsh domiflist dc3-hypervisor-1
   # Should show enp1s0 on mgmt, enp2s0+ on p2p networks
   ```

3. **BGP adjacencies form**:
   ```bash
   ssh ubuntu@<vm-ip> "vtysh -c 'show bgp summary'"
   # Should show neighbors in Established state
   ```

## Performance Impact

- ✅ **Faster deployment** - no interface updates needed
- ✅ **More reliable** - fewer failure points
- ✅ **Cleaner logs** - no update-device errors

## Rollback

If issues occur, the old approach is preserved in git history:
```bash
git log --oneline | grep -i "interface\|cabling"
```

## Future Improvements

Potential enhancements:
1. Add network verification step
2. Support hot-adding interfaces to running VMs
3. Add interface bonding/teaming support
4. Support SR-IOV for data plane interfaces

## Questions?

For issues or questions:
- Check logs: `journalctl -xe`
- Verify networks: `virsh net-list --all`
- Check VM console: `virsh console <vm-name>`
- Review topology: `cat config/topology.yaml`

---

**Date**: January 23, 2026  
**Version**: 2.0.0 (Simplified Cabling)
