# Platform Changes - Ubuntu 24.04 Linux Only

## Summary

The Virtual DC deployment system has been updated to support **Ubuntu 24.04 LTS ONLY**. All macOS support has been removed to streamline the codebase and focus on the primary target platform.

## Changes Made

### 1. README.md Updates

**Removed:**
- macOS installation instructions via Homebrew
- macOS-specific prerequisites and setup steps
- References to macOS compatibility

**Updated:**
- Operating system requirement now explicitly states "Ubuntu 24.04 LTS recommended"
- Prerequisites section focuses on Linux-only tools (apt, systemd)
- Browser launch commands changed from `open` (macOS) to `firefox`/`xdg-open` (Linux)
- Added clear warning: "This system is designed specifically for Ubuntu 24.04 LTS and requires KVM/QEMU virtualization which is Linux-only. macOS is not supported."

### 2. modules/prerequisites.sh Updates

**Removed:**
- macOS operating system detection (`Darwin`)
- macOS-specific tool version detection
- `install_macos_prerequisites()` function
- `install_rhel_prerequisites()` function (CentOS/RHEL/Fedora)
- Homebrew installation commands
- macOS-specific disk space checking (`df -g`)
- macOS-specific file age detection (`stat -f`)

**Updated:**
- Operating system check now only accepts Linux
- Added Ubuntu version detection and warning if not 24.04
- All installation commands updated to use `apt` package manager
- Tool installation instructions now point to Ubuntu-specific commands
- Virtualization support check simplified (removed macOS bypass)
- libvirt daemon check uses only `systemctl` commands
- File operations use Linux-specific `stat -c` instead of macOS `stat -f`

### 3. modules/validation.sh Updates

**Removed:**
- Homebrew installation instruction for `yq` tool

**Updated:**
- `yq` installation error message now provides Linux-specific download command

### 4. QUICKSTART.md

**Status:** Already Ubuntu-only
- No macOS references found
- All commands use Ubuntu/Debian package managers

### 5. CLEANUP_GUIDE.md

**Status:** Already Linux-focused
- No macOS-specific content
- All examples use Linux commands

## Platform Requirements (Current)

### Supported Operating System
- **Ubuntu 24.04 LTS (Noble Numbat)** - Primary and recommended
- Other Linux distributions may work but are not officially supported

### Unsupported Operating Systems
- ❌ macOS (all versions)
- ❌ Windows (including WSL)
- ❌ CentOS/RHEL/Fedora (removed in this update)

### Why Ubuntu 24.04 Only?

1. **KVM/QEMU Native Support**: Linux kernel-based virtualization
2. **libvirt Compatibility**: Best integration with Ubuntu's libvirt
3. **Cloud Image Availability**: Ubuntu 24.04 LTS cloud images used for hypervisors
4. **FRRouting Support**: Optimal BGP routing stack on Ubuntu
5. **SONiC Compatibility**: Network OS designed for Linux environments
6. **Consistency**: Hypervisor VMs run Ubuntu 24.04, host should match

## Migration Guide

If you were previously using this on macOS:

### Option 1: Use Ubuntu 24.04 Natively
1. Install Ubuntu 24.04 LTS on dedicated hardware
2. Follow installation instructions in README.md
3. Run deployment as usual

### Option 2: Use Ubuntu 24.04 VM on macOS
1. Install VirtualBox or VMware Fusion on macOS
2. Create Ubuntu 24.04 LTS VM (minimum 16GB RAM, 100GB disk)
3. Enable nested virtualization in VM settings
4. Install prerequisites inside Ubuntu VM
5. Run Virtual DC deployment inside the VM

**Note:** Nested virtualization may have performance limitations.

## Files Modified

```
usvf/virtual-dc/
├── README.md                    # Updated installation and requirements
├── modules/
│   ├── prerequisites.sh        # Removed macOS support code
│   └── validation.sh           # Updated error messages
└── PLATFORM_CHANGES.md         # This file
```

## Files Unchanged (Already Linux-Only)

```
usvf/virtual-dc/
├── QUICKSTART.md               # Already Ubuntu-focused
├── CLEANUP_GUIDE.md            # Already Linux commands only
├── USAGE_GUIDE.md              # Generic, no OS-specific content
├── modules/
│   ├── hypervisor.sh          # Uses libvirt (Linux-only)
│   ├── network.sh             # Uses libvirt networks
│   ├── switches.sh            # KVM/QEMU only
│   ├── bgp.sh                 # Cloud-init (works on Linux)
│   ├── cabling.sh             # libvirt-based
│   ├── cleanup.sh             # virsh commands (Linux)
│   └── verify.sh              # Generic checks
└── scripts/
    ├── deploy-virtual-dc.sh   # Shell script (Linux)
    ├── topology-builder.sh    # Shell script (Linux)
    └── graphical-designer.html # Browser-based (OS-agnostic)
```

## Testing

To verify the system works correctly on Ubuntu 24.04:

```bash
# 1. Check prerequisites
cd usvf/virtual-dc
./scripts/deploy-virtual-dc.sh --check-prereqs

# Expected output:
# ✓ Running on Ubuntu 24.04
# ✓ Hardware virtualization is enabled
# ✓ libvirt daemon is running
# ✓ All required tools installed
# ✓ Ubuntu 24.04 cloud image downloaded

# 2. Validate configuration
./scripts/deploy-virtual-dc.sh --validate

# 3. Deploy with example topology
./scripts/deploy-virtual-dc.sh

# 4. Verify deployment
virsh list --all
virsh net-list --all
```

## Compatibility Matrix

| Component | Ubuntu 24.04 | macOS | Windows |
|-----------|--------------|-------|---------|
| KVM/QEMU | ✅ Native | ❌ Not available | ❌ Not available |
| libvirt | ✅ Supported | ❌ Removed | ❌ Never supported |
| FRRouting | ✅ APT package | ❌ Homebrew (removed) | ❌ Not supported |
| Cloud-init | ✅ Native | ❌ Limited | ❌ Limited |
| Nested Virt | ✅ Full support | ❌ N/A | ❌ WSL2 limited |

## Benefits of Ubuntu-Only Approach

### Code Simplification
- ✅ Removed 200+ lines of macOS-specific code
- ✅ Eliminated OS detection logic
- ✅ Single installation path to maintain
- ✅ Consistent tooling across development and deployment

### Performance
- ✅ Native KVM performance (no overhead)
- ✅ Direct hardware access
- ✅ Better memory management
- ✅ Lower latency

### Reliability
- ✅ Single platform to test
- ✅ Predictable behavior
- ✅ Easier troubleshooting
- ✅ Better community support

### Development Focus
- ✅ More time for features
- ✅ Less time on compatibility
- ✅ Clearer documentation
- ✅ Simplified testing

## Future Considerations

This system is now optimized for Ubuntu 24.04 LTS. If other Linux distributions need to be supported in the future:

1. **Ubuntu-based distros** (Kubuntu, Xubuntu, etc.) - Should work with minimal changes
2. **Debian** - Similar to Ubuntu, may need package name adjustments
3. **Fedora/RHEL** - Would require adding back RPM-based installation
4. **Arch Linux** - Would require pacman package manager support

## Rollback

If you need to restore macOS support, you can:

```bash
git log --all --grep="macOS" --oneline
git revert <commit-hash>
```

Or restore from backup before this change.

## Version Information

- **Change Date**: January 20, 2026
- **Affected Version**: All future versions
- **Minimum Ubuntu Version**: 24.04 LTS
- **Target Platform**: x86_64 Linux with KVM support

## Contact

For questions about platform support:
- Check: [README.md](README.md) for current requirements
- Review: [QUICKSTART.md](QUICKSTART.md) for installation
- See: [USAGE_GUIDE.md](USAGE_GUIDE.md) for detailed usage

---

**Platform Support Summary**: Ubuntu 24.04 LTS Linux Only ✅
