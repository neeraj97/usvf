# SONiC Switch Deployment Guide

## Overview

This document explains how SONiC switches are deployed in the Virtual DC system using the SONiC-VS (Virtual Switch) approach.

## Deployment Method: SONiC-VS in Docker

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Switch VM (Ubuntu 24.04)               │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │         SONiC-VS Docker Container                 │  │
│  │                                                   │  │
│  │  - SONiC OS (debian-based)                       │  │
│  │  - FRRouting (BGP daemon)                        │  │
│  │  - SONiC CLI tools                               │  │
│  │  - Virtual switch dataplane                      │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  Management Interface (eth0) - 192.168.100.x/24        │
│  Data Interfaces (eth1, eth2, ...) - For BGP peering   │
└─────────────────────────────────────────────────────────┘
```

### Why SONiC-VS in Docker?

**Advantages:**
- ✅ **Easy Deployment**: Automated installation via cloud-init
- ✅ **Well Documented**: Official Microsoft/Azure SONiC project
- ✅ **Production Ready**: Used for SONiC development and testing
- ✅ **Manageable**: Standard Docker container lifecycle
- ✅ **Functional**: All SONiC features work identically
- ✅ **Resource Efficient**: Lightweight compared to full SONiC VM
- ✅ **Fast Startup**: Container starts in seconds

**vs. Native SONiC KVM:**
- Native SONiC KVM is harder to automate
- Complex initial configuration via serial console
- Management IP setup is more difficult
- Less documentation for virtualization

## Deployment Process

### Step 1: VM Creation

Each switch is deployed as an Ubuntu 24.04 VM with:
- **CPU**: 4 vCPUs
- **Memory**: 8GB RAM
- **Disk**: 50GB (thin-provisioned from Ubuntu base image)
- **Management Interface**: Connected to management network
- **Data Interfaces**: Multiple virtio interfaces for switch ports

### Step 2: Cloud-Init Setup

Cloud-init automatically:
1. Configures hostname and management IP
2. Installs Docker and dependencies
3. Downloads SONiC-VS Docker image (~2GB)
4. Creates systemd service for SONiC-VS
5. Starts the SONiC-VS container
6. Reboots the VM for clean startup

### Step 3: SONiC Container Startup

The SONiC-VS container:
- Runs in **privileged mode** (needed for network namespace access)
- Uses **host networking** (for direct interface access)
- Mounts `/etc/sonic` for persistent configuration
- Auto-starts on boot via systemd service

### Step 4: Configuration

Initial SONiC configuration includes:
- Device metadata (hostname, ASN, platform)
- Loopback interface with router ID
- BGP daemon ready for peering

## Accessing SONiC Switches

### SSH to Switch VM

```bash
# SSH to the Ubuntu VM
ssh -i config/virtual-dc-lab-ssh-key ubuntu@192.168.100.101

# Username: ubuntu
# Password: ubuntu (for console access)
```

### Access SONiC Container

Once SSH'd into the VM:

```bash
# Enter SONiC container
docker exec -it sonic-vs bash

# Now you're in SONiC OS
admin@sonic:~$ 
```

### Quick Access Aliases

The system creates convenient aliases:

```bash
# Shortcut to enter SONiC
sonic

# Run SONiC CLI commands directly
sonic-cli

# View container logs
sonic-logs
```

## SONiC CLI Commands

### Show System Status

```bash
# Inside SONiC container
show system-health summary
show version
show platform summary
```

### Interface Management

```bash
# Show all interfaces
show interface status

# Show specific interface
show interface status Ethernet0

# Configure interface (example)
config interface ip add Ethernet0 10.0.0.1/24
config interface startup Ethernet0
```

### BGP Operations

```bash
# Show BGP summary
show ip bgp summary

# Show BGP neighbors
show ip bgp neighbors

# Show BGP routes
show ip bgp

# Show specific neighbor
show ip bgp neighbors 10.0.0.2
```

### Configuration Management

```bash
# Show running configuration
show runningconfiguration all

# Save configuration
config save -y

# Load configuration
config load /etc/sonic/config_db.json -y

# Reset to factory defaults
config reload -y
```

### Debugging

```bash
# Show logs
show logging

# Show tech support (comprehensive diagnostics)
show techsupport

# Access vtysh (FRRouting shell)
vtysh
```

## SONiC Configuration Files

### Location in Container

- **Main Config**: `/etc/sonic/config_db.json`
- **FRR Config**: `/etc/frr/frr.conf`
- **Logs**: `/var/log/syslog`

### Configuration Database (config_db.json)

SONiC uses a JSON-based configuration:

```json
{
    "DEVICE_METADATA": {
        "localhost": {
            "hostname": "leaf-1",
            "hwsku": "Force10-S6000",
            "platform": "x86_64-kvm_x86_64-r0",
            "mac": "auto",
            "type": "ToRRouter",
            "bgp_asn": "65101"
        }
    },
    "LOOPBACK_INTERFACE": {
        "Loopback0|2.2.2.1/32": {}
    },
    "BGP_NEIGHBOR": {
        "Ethernet0|10.0.0.2": {
            "asn": "65001",
            "name": "hypervisor-1"
        }
    }
}
```

## Container Management

### Start/Stop Container

```bash
# On the Ubuntu VM (not inside container)

# Stop SONiC container
sudo systemctl stop sonic-vs

# Start SONiC container
sudo systemctl start sonic-vs

# Restart container
sudo systemctl restart sonic-vs

# Check status
sudo systemctl status sonic-vs
```

### Docker Commands

```bash
# View container status
docker ps | grep sonic-vs

# View container logs
docker logs sonic-vs

# Follow logs in real-time
docker logs -f sonic-vs

# Inspect container
docker inspect sonic-vs

# View resource usage
docker stats sonic-vs
```

## Troubleshooting

### Container Not Starting

```bash
# Check Docker service
sudo systemctl status docker

# Check sonic-vs service
sudo systemctl status sonic-vs

# View service logs
sudo journalctl -u sonic-vs -f

# Manually start container
sudo /home/ubuntu/start-sonic.sh
```

### SONiC Not Responding

```bash
# Restart container
sudo systemctl restart sonic-vs

# Check if container is running
docker ps | grep sonic-vs

# View container logs
docker logs sonic-vs
```

### Network Issues

```bash
# Inside SONiC container
show interface status

# Check if interfaces are up
ip link show

# Ping test
ping -c 3 192.168.100.1
```

### BGP Not Working

```bash
# Inside SONiC container
show ip bgp summary
show ip bgp neighbors

# Access FRR shell for detailed debugging
vtysh
show bgp summary
show bgp neighbors
```

## Image Information

### SONiC-VS Docker Image

- **Registry**: `docker.io/sonicdev/docker-sonic-vs`
- **Tag**: `latest` (or specific version like `202311`)
- **Size**: ~2GB compressed
- **Base OS**: Debian
- **Components**:
  - SONiC platform layer
  - FRRouting (BGP/OSPF/IS-IS)
  - Redis database
  - Python utilities
  - SONiC CLI tools

### Updating SONiC Image

```bash
# On Ubuntu VM
docker pull docker.io/sonicdev/docker-sonic-vs:latest

# Restart with new image
sudo systemctl restart sonic-vs
```

## Best Practices

### 1. Save Configuration Changes

```bash
# Inside SONiC
config save -y
```

This ensures your changes persist across container restarts.

### 2. Use Systemd Service

Always use the systemd service to manage SONiC:
```bash
sudo systemctl start/stop/restart sonic-vs
```

### 3. Monitor Container Health

```bash
# Check if container is healthy
docker ps | grep sonic-vs
systemctl status sonic-vs
```

### 4. Regular Backups

```bash
# Backup configuration
docker exec sonic-vs cat /etc/sonic/config_db.json > backup.json
```

### 5. Log Management

SONiC generates logs. Monitor them:
```bash
docker logs sonic-vs --since 1h
```

## Integration with Virtual DC

### Management Network

- Each switch VM gets a management IP: `192.168.100.101+`
- Accessible via SSH from the host
- Used for configuration and monitoring

### Data Network

- Multiple network interfaces connected to hypervisors
- BGP unnumbered for peering
- IPv6 link-local addresses for BGP sessions

### BGP Configuration

BGP is configured by the Virtual DC deployment system:
- Interfaces are enabled
- BGP unnumbered is set up
- Neighbors are auto-discovered
- Route reflector configuration (for spines)

## Performance Characteristics

### Resource Usage

- **CPU**: ~1-2% idle, ~10-20% under load
- **Memory**: ~2-3GB RAM
- **Disk**: ~5GB for container image + logs
- **Network**: Line-rate switching within virtualization limits

### Capacity

- **Max Ports**: Depends on VM network interfaces (typically 32-64)
- **BGP Routes**: Can handle thousands of routes
- **BGP Peers**: Dozens of peers supported

## Limitations

1. **Not Hardware Switch**: This is a virtual switch for lab/testing
2. **Throughput**: Limited by VM networking (not line-rate)
3. **ASIC Features**: Some hardware-specific features not available
4. **Scale**: Smaller scale than physical SONiC switches

## References

- [SONiC GitHub](https://github.com/sonic-net/SONiC)
- [SONiC Wiki](https://github.com/sonic-net/SONiC/wiki)
- [SONiC-VS Documentation](https://github.com/sonic-net/sonic-buildimage/blob/master/platform/vs/README.md)
- [FRRouting Documentation](https://docs.frrouting.org/)

## Support

For issues with SONiC deployment:
1. Check container logs: `docker logs sonic-vs`
2. Check systemd service: `systemctl status sonic-vs`
3. Verify VM network connectivity
4. Review SONiC configuration: `/etc/sonic/config_db.json`
