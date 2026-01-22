# Virtual DC Network Resource Naming Fix

## Issue Summary

P2P link configurations and network resources were being created without datacenter name prefixes, causing:

1. **Improper Resource Isolation** - Networks from different VDCs could conflict
2. **Cleanup Failures** - Couldn't identify which networks belonged to which datacenter
3. **Multi-VDC Support Broken** - Multiple datacenters couldn't coexist
4. **Inconsistent Naming** - VMs had prefixes but networks didn't

## Root Cause

The cabling module was creating:
- Network configs in `config/` instead of `config/vdc-{dcname}/`
- Network names like `p2p-link-0` instead of `{dcname}-p2p-link-0`
- Bridge names like `virbr-p2p-0` instead of `virbr-{dcname}-p2p-0`

## Changes Made

### 1. **cabling.sh** - Network Creation with DC Prefix

#### Before:
```bash
create_p2p_network() {
    local src_device="$1"
    local network_name="p2p-link-${link_id}"
    local network_xml="$PROJECT_ROOT/config/${network_name}.xml"
    
    cat > "$network_xml" <<EOF
<network>
  <name>$network_name</name>
  <bridge name='vbr-p2p-${link_id}' />
</network>
EOF
}
```

#### After:
```bash
create_p2p_network() {
    local config_file="$1"
    local dc_name=$(yq eval '.global.datacenter_name' "$config_file")
    local network_name="${dc_name}-p2p-link-${link_id}"
    local network_xml=$(get_vdc_network_xml "$dc_name" "${network_name}")
    
    cat > "$network_xml" <<EOF
<network>
  <name>$network_name</name>
  <bridge name='vbr-${dc_name}-p2p-${link_id}' />
</network>
EOF
}
```

**Key Changes:**
- Added `config_file` parameter to all functions
- Network names: `p2p-link-X` → `{dcname}-p2p-link-X`
- Bridge names: `virbr-p2p-X` → `virbr-{dcname}-p2p-X`
- Config path: `config/` → `config/vdc-{dcname}/networks/`
- VM names: `{vm}` → `{dcname}-{vm}` when attaching interfaces

### 2. **cleanup.sh** - Network Cleanup Pattern

#### Before:
```bash
destroy_virtual_networks() {
    local network_patterns=(
        "${dc_name}-mgmt"
        "${dc_name}-data"
        "${dc_name}-fabric"
        "virtual-dc-.*"
    )
}
```

#### After:
```bash
destroy_virtual_networks() {
    local network_patterns=(
        "${dc_name}-mgmt"
        "${dc_name}-data"
        "${dc_name}-fabric"
        "${dc_name}-p2p-link-.*"  # Added for P2P links
        "virtual-dc-.*"
    )
}
```

**Key Changes:**
- Added `${dc_name}-p2p-link-.*` pattern for proper cleanup
- Network XML file removal added to `cleanup_cabling()`

### 3. **Function Signature Updates**

All cabling functions now accept `config_file` as first parameter:

```bash
# Old signatures
create_p2p_network "$src_device" "$src_iface" "$dst_device" "$dst_iface" "$link_id"
attach_interface_to_vm "$vm_name" "$iface_name" "$link_id"

# New signatures
create_p2p_network "$config_file" "$src_device" "$src_iface" "$dst_device" "$dst_iface" "$link_id"
attach_interface_to_vm "$config_file" "$vm_name" "$iface_name" "$link_id"
```

## Resource Naming Convention

### Complete Naming Scheme

| Resource Type | Format | Example (prod datacenter) |
|--------------|--------|---------------------------|
| **Virtual Machines** | `{dcname}-{vmname}` | `prod-hv1`, `prod-leaf1` |
| **Management Network** | `{dcname}-mgmt` | `prod-mgmt` |
| **Data Network** | `{dcname}-data` | `prod-data` |
| **P2P Link Networks** | `{dcname}-p2p-link-{id}` | `prod-p2p-link-0` |
| **Bridge Devices** | `vbr-{dcname}-{type}-{id}` | `vbr-prod-p2p-0` |
| **Network XML Files** | `config/vdc-{dcname}/networks/{name}.xml` | `config/vdc-prod/networks/prod-p2p-link-0.xml` |
| **VM Disks** | `config/vdc-{dcname}/disks/{vmname}.qcow2` | `config/vdc-prod/disks/prod-hv1.qcow2` |

### Directory Structure

```
config/
└── vdc-{dcname}/
    ├── networks/
    │   ├── {dcname}-mgmt.xml
    │   ├── {dcname}-data.xml
    │   ├── {dcname}-p2p-link-0.xml
    │   ├── {dcname}-p2p-link-1.xml
    │   └── ...
    ├── disks/
    │   ├── {dcname}-hv1.qcow2
    │   ├── {dcname}-leaf1.qcow2
    │   └── ...
    ├── cloud-init/
    │   ├── {dcname}-hv1/
    │   ├── {dcname}-leaf1/
    │   └── ...
    └── bgp-configs/
        ├── {dcname}-hv1.conf
        └── ...
```

## Benefits

### 1. **Proper Multi-VDC Support**
```bash
# Can now run multiple datacenters simultaneously
./vdc-manager.sh create prod --config prod-topology.yaml
./vdc-manager.sh create staging --config staging-topology.yaml
./vdc-manager.sh create dev --config dev-topology.yaml

# Resources are properly isolated:
# - prod-hv1, prod-p2p-link-0
# - staging-hv1, staging-p2p-link-0
# - dev-hv1, dev-p2p-link-0
```

### 2. **Clean Destruction**
```bash
# Destroy specific datacenter
./vdc-manager.sh destroy prod

# Only removes resources matching:
# - VMs: prod-*
# - Networks: prod-mgmt, prod-data, prod-p2p-link-*
# - Files: config/vdc-prod/*
```

### 3. **Easy Resource Tracking**
```bash
# List all resources for a datacenter
virsh list --all | grep "^prod-"
virsh net-list --all | grep "^prod-"
ls config/vdc-prod/networks/

# Output:
# prod-hv1
# prod-hv2
# prod-leaf1
# prod-spine1
# prod-mgmt
# prod-p2p-link-0
# prod-p2p-link-1
```

### 4. **Consistent Naming Across All Resources**

All resources follow the same pattern: `{datacenter}-{resource}`

## Testing Recommendations

### 1. Single Datacenter Deployment
```bash
# Deploy
./vdc-manager.sh create prod --config config/topology.yaml

# Verify networks
virsh net-list --all | grep "^prod-"
# Should show: prod-mgmt, prod-p2p-link-0, prod-p2p-link-1, etc.

# Verify VMs
virsh list --all | grep "^prod-"
# Should show: prod-hv1, prod-hv2, prod-leaf1, prod-spine1, etc.

# Verify files
ls config/vdc-prod/networks/
# Should show: prod-mgmt.xml, prod-p2p-link-*.xml

# Cleanup
./vdc-manager.sh destroy prod
```

### 2. Multi-Datacenter Deployment
```bash
# Deploy multiple DCs
./vdc-manager.sh create prod --config config/prod-topology.yaml
./vdc-manager.sh create staging --config config/staging-topology.yaml

# Verify isolation
virsh net-list --all | grep "^prod-"
virsh net-list --all | grep "^staging-"

# Destroy one without affecting the other
./vdc-manager.sh destroy staging
virsh net-list --all | grep "^prod-"  # Should still show prod networks
```

### 3. Network Configuration Verification
```bash
# Check network XML files are in correct location
ls -la config/vdc-prod/networks/
ls -la config/vdc-staging/networks/

# Should NOT have files in root config/
ls config/*.xml  # Should be empty or not exist
```

## Migration Notes

### For Existing Deployments

If you have existing VDCs deployed with the old naming scheme:

1. **Backup current state:**
   ```bash
   virsh list --all > vms-backup.txt
   virsh net-list --all > networks-backup.txt
   ```

2. **Destroy old deployment:**
   ```bash
   ./vdc-manager.sh destroy {dcname}
   ```

3. **Clean up old network XMLs:**
   ```bash
   rm -f config/p2p-link-*.xml
   ```

4. **Redeploy with new naming:**
   ```bash
   ./vdc-manager.sh create {dcname} --config config/topology.yaml
   ```

### No Manual Migration Needed

The fix is fully backward compatible - new deployments will automatically use the correct naming convention.

## Files Modified

1. `usvf/virtual-dc/modules/cabling.sh` - Network creation and interface attachment
2. `usvf/virtual-dc/modules/cleanup.sh` - Network cleanup patterns
3. `usvf/virtual-dc/modules/hypervisor.sh` - VM naming (already fixed)
4. `usvf/virtual-dc/modules/switches.sh` - VM naming (already fixed)

## Related Documentation

- See `VM_NAMING_FIX.md` for VM naming convention details
- See `USAGE_GUIDE.md` for deployment procedures
- See `MIGRATION_SUMMARY.md` for overall architecture changes
