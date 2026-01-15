# Hardware Telemetry System

A comprehensive hardware monitoring and telemetry collection system for Linux servers. This system automatically detects and monitors all hardware components, collecting detailed metrics at regular intervals.

## Overview

The Hardware Telemetry System provides detailed monitoring for:

- **CPU**: Frequency, temperature, throttling, cache stats, power consumption
- **Memory**: Usage, errors, bandwidth, per-DIMM information, NUMA stats
- **Storage**: SMART data, temperature, wear level, TRIM status, I/O statistics (SSD/HDD/NVMe)
- **Network**: Bandwidth, errors, drops, temperature, link status, queue statistics
- **GPU**: Temperature, usage, memory, power, fan speed, clock speed (NVIDIA/AMD/Intel)
- **Motherboard**: BIOS info, manufacturer, model, serial numbers
- **Thermal**: All system temperature sensors
- **Power**: Power consumption, PSU status, battery (if applicable)
- **PCIe**: Device enumeration, link status and speed
- **USB**: Connected device inventory
- **RAID**: Controller status, array health, disk health
- **BMC/IPMI**: Baseboard Management Controller sensors and status

## Features

- **Modular Architecture**: Each hardware component has its own telemetry module
- **Configurable**: Extensive configuration options for each module
- **Dual Output Formats**: Human-readable text files and structured JSON
- **Interval-based Collection**: Different file for each collection interval
- **Automatic File Rotation**: Configurable retention policy
- **Alert Thresholds**: Built-in warning and critical thresholds
- **Comprehensive Coverage**: Monitors all devices from motherboard to peripherals
- **Vendor Support**: Works with various hardware vendors (Intel, AMD, NVIDIA, etc.)

## Directory Structure

```
hardware-telemetry/
├── telemetry-collector.sh    # Main collection script
├── config/
│   └── telemetry.conf         # Configuration file
├── modules/
│   ├── utils.sh               # Utility functions
│   ├── cpu_telemetry.sh       # CPU monitoring
│   ├── memory_telemetry.sh    # Memory monitoring
│   ├── storage_telemetry.sh   # Storage monitoring
│   ├── network_telemetry.sh   # Network monitoring
│   ├── gpu_telemetry.sh       # GPU monitoring
│   └── system_telemetry.sh    # System-wide monitoring
├── data/                      # Telemetry output directory
├── logs/                      # Log files
├── README.md                  # This file
└── USAGE_GUIDE.md            # Detailed usage instructions
```

## Quick Start

### 1. Make Scripts Executable

```bash
chmod +x telemetry-collector.sh
chmod +x modules/*.sh
```

### 2. Run Single Collection

```bash
sudo ./telemetry-collector.sh --once
```

### 3. Run Continuous Collection

```bash
sudo ./telemetry-collector.sh
```

### 4. Run Limited Collections

```bash
# Collect 10 samples
sudo ./telemetry-collector.sh --count 10
```

## Requirements

### Required Tools

- `bash` (4.0+)
- `lscpu`
- `free`
- `lsblk`
- `ip`
- `bc`

### Optional Tools (for enhanced telemetry)

- `dmidecode` - Motherboard and DIMM information
- `smartctl` (smartmontools) - Storage SMART data
- `sensors` (lm-sensors) - Temperature sensors
- `nvidia-smi` - NVIDIA GPU monitoring
- `rocm-smi` - AMD GPU monitoring
- `ethtool` - Network interface details
- `ipmitool` - BMC/IPMI monitoring
- `nvme-cli` - NVMe specific commands
- `hdparm` - Hard drive parameters
- `iostat` (sysstat) - I/O statistics
- `sar` (sysstat) - Network statistics
- `perf` - Performance monitoring
- `turbostat` - CPU power statistics
- `numactl` - NUMA information
- `lspci` - PCIe devices
- `lsusb` - USB devices
- `megacli`/`storcli` - MegaRAID controllers
- `mdadm` - Software RAID

### Installing Tools

**Debian/Ubuntu:**
```bash
sudo apt-get update
sudo apt-get install -y lm-sensors smartmontools sysstat \
    ethtool ipmitool nvme-cli hdparm pciutils usbutils \
    linux-tools-generic dmidecode numactl
```

**RHEL/CentOS/Rocky:**
```bash
sudo yum install -y lm_sensors smartmontools sysstat \
    ethtool ipmitool nvme-cli hdparm pciutils usbutils \
    perf dmidecode numactl
```

## Configuration

Edit `config/telemetry.conf` to customize:

- Collection intervals
- Enable/disable specific modules
- Alert thresholds
- Output directories
- File rotation settings
- Per-module detailed options

See `USAGE_GUIDE.md` for detailed configuration instructions.

## Output Files

### Text Files

Located in `data/` directory with format: `telemetry_YYYYMMDD_HHMMSS.txt`

Contains human-readable telemetry data organized by module with clear sections and labels.

### JSON Files

Located in `data/` directory with format: `telemetry_YYYYMMDD_HHMMSS.json`

Contains structured JSON data suitable for parsing, analysis, and integration with monitoring systems.

### Log Files

Located in `logs/` directory with format: `telemetry_YYYYMMDD.log`

Contains operational logs including errors, warnings, and collection status.

## Permissions

Some telemetry data requires root access:
- SMART data
- DMI/SMBIOS information
- Hardware sensors
- PCIe configuration space
- IPMI/BMC access

Run with `sudo` for complete telemetry collection.

## Use Cases

- **Server Monitoring**: Continuous hardware health monitoring
- **Performance Analysis**: Identify hardware bottlenecks
- **Predictive Maintenance**: Track wear levels and error rates
- **Capacity Planning**: Monitor resource utilization trends
- **Troubleshooting**: Detailed hardware state snapshots
- **Compliance**: Hardware inventory and documentation

## Integration

The JSON output format makes it easy to integrate with:
- Monitoring systems (Prometheus, Grafana, Nagios)
- Log aggregators (ELK Stack, Splunk)
- Cloud monitoring (AWS CloudWatch, Azure Monitor)
- Custom analysis tools and dashboards

## Best Practices

1. **Collection Interval**: Balance between data granularity and overhead (default: 300s)
2. **File Rotation**: Enable automatic cleanup to prevent disk space issues
3. **Root Access**: Run with sudo for complete telemetry
4. **Alert Thresholds**: Adjust thresholds based on your hardware specifications
5. **Module Selection**: Disable unnecessary modules to reduce overhead
6. **Storage**: Ensure adequate disk space for telemetry data

## Troubleshooting

### Missing Data

- Verify required tools are installed
- Check permissions (run with sudo)
- Review logs in `logs/` directory
- Ensure hardware supports the feature (e.g., SMART, sensors)

### High CPU Usage

- Increase collection interval
- Disable resource-intensive modules
- Reduce number of concurrent collections

### Disk Space

- Enable file rotation
- Reduce MAX_FILES_TO_KEEP
- Consider compression for archived files

## Support

For issues, questions, or contributions, please refer to the main project documentation.

## License

This software is part of the USVF (Universal Server Validation Framework) project.

## Version

1.0.0 - Initial Release

## Authors

Part of the USVF Hardware Testing Suite
