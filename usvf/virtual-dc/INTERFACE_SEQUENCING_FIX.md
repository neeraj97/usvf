# Interface Sequencing Fix

## Issue Summary

Virtual machine network interfaces were not being created in the correct sequential order matching the topology configuration, causing incorrect cabling connections and BGP neighbor mismatches.

## The Problem

### Previous Behavior (BROKEN)

1. **VMs created with only management interface** (enp1s0)
2. **Cabling module dynamically attached interfaces** using `virsh attach-interface`
3. **Interfaces attached in cable definition order**, NOT topology interface order

### Example of the Problem

Given topology.yaml:
```yaml
hypervisors:
  - name: "hypervisor-1"
    data_interfaces:
      - name: "enp2s0"  # Should connect to Leaf-1
        description: "Connection to Leaf-1"
      - name: "enp3s0"  # Should connect to Leaf-2
        description: "Connection to Leaf-2"

cabling:
  - source:
      device: "hypervisor-1"
      interface: "enp3s0"  # Cable 0: Leaf-2 connection
    destination:
      device: "leaf-2"
      interface: "enp2s0"
      
  - source:
      device: "hypervisor-1"
      interface: "enp2s0"  # Cable 1: Leaf-1 connection
    destination:
      device: "leaf-1"
      interface: "enp2s0"
```

**What Happened:**
- Cable 0 attached first → created **enp2s0** (but connected to Leaf-2) ❌
- Cable 1 attached second → created **enp3s0** (but connected to Leaf-1) ❌

**Result:** BGP configuration referenced the wrong interfaces!
- FRR configured: `neighbor enp2s0` expecting Leaf-1, but it was Leaf-2
- FRR configured: `neighbor enp3s0` expecting Leaf-2, but it was Leaf-1

## The Solution

### New Behavior (FIXED)

1. **VMs created with ALL interfaces** during initial VM creation
2. **Interfaces created in sequential PCI slot order** (enp1s0, enp2s0, enp3s0, enp4s0, etc.)
3. **Initially connected to default network** (placeholder)
4. **Cabling module UPDATES interfaces** to correct P2P networks based on interface name

### How It Works Now

#### Step 1: VM Creation (hypervisor.sh, switches.sh)

```bash
# Create VM with management + data interfaces
virt-install \
  --name dc3-hypervisor-1 \
  --network network=dc3-mgmt,model=virtio \     # enp1s0 (management)
  --network network=default,model=virtio \       # enp2s0 (placeholder)
  --network network=default,model=virtio \       # enp3s0 (placeholder)
  ...
```

**Result:** Predictable interface names in correct PCI slots
- PCI Slot 1 → enp1s0 (management)
- PCI Slot 2 → enp2s0 (data - placeholder)
- PCI Slot 3 → enp3s0 (data - placeholder)
- PCI Slot 4 → enp4s0 (data - placeholder)

#### Step 2: Cabling Configuration (cabling.sh)

```bash
# For each cable in topology.yaml
# Extract interface name from cable definition
# Update the EXISTING interface to the correct P2P network

# Cable: hypervisor-1:enp2s0 → leaf-1
# Find PCI slot for enp2s0 (slot 2)
# Update that slot's network to dc3-p2p-link-X

virsh update-device dc3-hypervisor-1 \
  <interface with PCI slot 2> \
  --config --persistent
```

**Result:** Correct interface-to-network mapping
- enp2s0 → Connected to Leaf-1 ✓
- enp3s0 → Connected to Leaf-2 ✓

## Changes Made

### 1. hypervisor.sh - `create_hypervisor_vm()`

**Before:**
```bash
# Only management interface
virt-install \
  --network network=$mgmt_network,model=virtio \
  ...
```

**After:**
```bash
# Management + all data interfaces
virt-install \
  --network network=$mgmt_network,model=virtio \
  ...

# Add data plane interfaces in sequential order
for i in $(seq 1 $iface_count); do
    cmd="$cmd --network network=default,model=virtio"
done
```

### 2. switches.sh - `create_sonic_vm()`

Same changes as hypervisor.sh - create all interfaces during VM creation.

### 3. cabling.sh - `attach_interface_to_vm()`

**Before:**
```bash
# Attach NEW interface to VM
virsh attach-interface "$vm_name" \
  --type network \
  --source "$network_name" \
  --model virtio \
  ...
```

**After:**
```bash
# Update EXISTING interface's network
# Extract PCI slot from interface name
local slot_num=$(echo "$iface_name" | grep -oP 'enp\K\d+')
local pci_addr=$(printf "0000:00:%02x.0" "$slot_num")

# Create XML for interface at specific PCI slot
cat > "$temp_xml" <<EOF
<interface type='network'>
  <source network='$network_name'/>
  <model type='virtio'/>
  <address type='pci' slot='0x$(printf "%x" "$slot_num")' .../>
</interface>
EOF

# Update the interface
virsh update-device "$vm_name" "$temp_xml" --config
```

## Interface Naming Convention

### Understanding Predictable Network Names

Ubuntu 24.04 uses predictable network interface names based on PCI topology:

| PCI Slot | Interface Name | Purpose |
|----------|---------------|---------|
| Slot 1 | enp1s0 | Management network |
| Slot 2 | enp2s0 | 1st data interface |
| Slot 3 | enp3s0 | 2nd data interface |
| Slot 4 | enp4s0 | 3rd data interface |
| Slot 5 | enp5s0 | 4th data interface |
| Slot N | enp{N}s0 | (N-1)th data interface |

Format: `enp{pci_slot}s0`
- `en` = Ethernet
- `p{N}` = PCI slot number
- `s0` = Slot 0 (always 0 for virtio devices)

### Topology Configuration

Your topology.yaml should list interfaces in the order you want them created:

```yaml
hypervisors:
  - name: "hypervisor-1"
    management:
      interface: "enp1s0"  # Always first (PCI slot 1)
    data_interfaces:
      - name: "enp2s0"     # PCI slot 2
        description: "Connection to Leaf-1"
      - name: "enp3s0"     # PCI slot 3
        description: "Connection to Leaf-2"
      - name: "enp4s0"     # PCI slot 4
        description: "Connection to Leaf-3"
```

### Cabling Configuration

Reference interfaces by their names - the system will ensure correct mapping:

```yaml
cabling:
  - source:
      device: "hypervisor-1"
      interface: "enp2s0"  # This WILL be PCI slot 2
    destination:
      device: "leaf-1"
      interface: "enp2s0"
      
  - source:
      device: "hypervisor-1"
      interface: "enp3s0"  # This WILL be PCI slot 3
    destination:
      device: "leaf-2"
      interface: "enp3s0"
```

## Benefits

### 1. **Predictable Interface Order**
Interfaces are always created in the same order, matching topology configuration.

### 2. **Correct BGP Configuration**
FRR configuration matches actual physical connectivity:
```
router bgp 65001
 neighbor enp2s0 interface peer-group FABRIC  # Actually connects to Leaf-1
 neighbor enp3s0 interface peer-group FABRIC  # Actually connects to Leaf-2
```

### 3. **Easier Troubleshooting**
```bash
# Check interface on VM
virsh domiflist dc3-hypervisor-1

# Output shows interfaces in order:
# enp1s0 -> dc3-mgmt (management)
# enp2s0 -> dc3-p2p-link-0 (to Leaf-1)
# enp3s0 -> dc3-p2p-link-1 (to Leaf-2)
```

### 4. **Topology Flexibility**
You can define cables in any order in topology.yaml - interfaces will still be created sequentially.

## Verification

### Check VM Interfaces

```bash
# List all interfaces on a VM
virsh domiflist dc3-hypervisor-1

# Output:
# Interface   Type      Source           Model    MAC
# -------------------------------------------------------
# vnet0       network   dc3-mgmt         virtio   52:54:00:xx:xx:xx
# vnet1       network   dc3-p2p-link-0   virtio   52:54:00:xx:xx:xx
# vnet2       network   dc3-p2p-link-1   virtio   52:54:00:xx:xx:xx
```

### Check Interface Inside VM

```bash
# SSH into VM
ssh ubuntu@192.168.100.11

# List interfaces
ip link show

# Output:
# 1: lo: ...
# 2: enp1s0: ... (management)
# 3: enp2s0: ... (data - to Leaf-1)
# 4: enp3s0: ... (data - to Leaf-2)
```

### Verify BGP Neighbors

```bash
# On hypervisor VM
vtysh -c "show bgp summary"

# Should show neighbors on correct interfaces:
# Neighbor     V   AS   MsgRcvd  MsgSent  ...
# enp2s0       4 65101    ...     ...      # Leaf-1 (ASN 65101)
# enp3s0       4 65102    ...     ...      # Leaf-2 (ASN 65102)
```

## Migration from Old Deployments

If you have VMs deployed with the old broken behavior:

### Option 1: Destroy and Recreate (Recommended)

```bash
# Destroy existing VDC
./vdc-manager.sh destroy {dcname}

# Create new VDC with fixed interface sequencing
./vdc-manager.sh create {dcname} --config topology.yaml
```

### Option 2: Manual Fix (Advanced)

```bash
# For each VM, shut down
virsh shutdown dc3-hypervisor-1

# Detach all data interfaces
virsh detach-interface dc3-hypervisor-1 network --config
virsh detach-interface dc3-hypervisor-1 network --config

# Start VM to regenerate with virt-install
# (This requires more manual work - Option 1 is easier)
```

## Related Documentation

- See `NETWORK_NAMING_FIX.md` for network/bridge naming conventions
- See `VM_NAMING_FIX.md` for VM naming conventions
- See `USAGE_GUIDE.md` for deployment procedures
- See `topology.yaml` for interface configuration examples

## Technical Details

### PCI Slot Allocation

KVM/QEMU assigns PCI slots sequentially to virtio devices:
1. First `--network` option → PCI slot 1 (0000:00:01.0)
2. Second `--network` option → PCI slot 2 (0000:00:02.0)
3. Third `--network` option → PCI slot 3 (0000:00:03.0)
4. Etc.

### Why This Approach

**Why not rely on attach order?**
- `virsh attach-interface` is asynchronous and order-dependent
- Interface names depend on kernel enumeration order
- Difficult to guarantee consistent ordering across reboots

**Why create placeholders?**
- Ensures consistent PCI slot allocation
- Allows interface updates without changing VM definition
- Works with both running and stopped VMs

**Why use interface names in topology?**
- Clear, self-documenting configuration
- Matches actual interface names in guest OS
- Easier to troubleshoot and verify

## Summary

The interface sequencing fix ensures that:
1. ✅ VM interfaces are created in predictable order
2. ✅ Interface names match their PCI slot positions
3. ✅ Cabling connects the correct interfaces
4. ✅ BGP configuration references correct neighbors
5. ✅ Topology is easy to understand and maintain

This fix is essential for proper BGP unnumbered operation and network connectivity in the Virtual DC!
