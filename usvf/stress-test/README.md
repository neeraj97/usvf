# USVF - Unified Server Validation Framework v3.0

Comprehensive server stress testing and benchmarking suite designed to push servers to their limits while monitoring all critical components.

## Overview

USVF is a modular, extensible framework for:
- **Hardware Discovery**: Automatically detects CPUs, memory, storage devices (NVMe/SSD/HDD), network interfaces (including smart NICs like Mellanox), and PCI devices
- **Comprehensive Stress Testing**: Simultaneously tests CPU, memory, storage, and network while distributing workload across cores
- **Real-time Monitoring**: Tracks temperatures, fan speeds, power consumption, and memory errors via BMC/IPMI and lm-sensors
- **Detailed Reporting**: Generates comprehensive reports with hardware specifications, test results, and performance metrics

## Features

### ✓ Intelligent Hardware Detection
- CPU topology and specifications
- Memory configuration (type, speed, DIMMs)
- Storage devices (NVMe, SSD, HDD) with model numbers and serial numbers
- Network interfaces with driver and firmware information
- Special PCI devices (GPUs, RAID controllers, InfiniBand/RDMA)
- BMC/IPMI availability

### ✓ Distributed Workload Testing
- **CPU Stress** (40% of cores): Matrix multiplication, FFT, floating-point operations
- **Storage Stress** (30% of cores): Sequential/random read/write with device-specific optimization
- **Network Stress** (20% of cores): TCP/UDP throughput testing per interface
- **Memory Stress** (10% of cores): Data integrity verification, bandwidth, and latency tests

### ✓ Real-time Monitoring
- CPU temperature (average and peak)
- Fan speeds across all sensors
- Power consumption (instantaneous and peak)
- Memory errors (EDAC correctable/uncorrectable)
- Thermal safety cutoff at 95°C

### ✓ Comprehensive Reporting
- Hardware inventory with model numbers
- Per-device benchmark results
- Storage IOPS and bandwidth metrics
- Network throughput statistics
- Monitoring telemetry summaries
- Unknown/untested device list for manual review

## Quick Start

### Installation

1. **Clone or download** the framework to your server
2. **Navigate** to the stress-test directory
3. **Run as root** (required for hardware access and stress testing):

```bash
cd usvf/stress-test
sudo ./server-stress.sh [duration_seconds]
```

### Basic Usage

```bash
# Run with default duration (600 seconds / 10 minutes)
sudo ./server-stress.sh

# Run for custom duration (e.g., 1800 seconds / 30 minutes)
sudo ./server-stress.sh 1800

# Run for 1 hour
sudo ./server-stress.sh 3600
```

### What Happens During Testing

1. **Dependency Installation**: Auto-installs required tools (stress-ng, fio, iperf3, etc.)
2. **Hardware Discovery**: Scans and catalogs all server components
3. **Core Distribution**: Allocates CPU cores across different test types
4. **Parallel Execution**: Launches all stress tests simultaneously
5. **Real-time Monitoring**: Displays live temperature, fan, and power metrics
6. **Report Generation**: Creates detailed reports in `/var/log/usvf_stress_[timestamp]/`

## Output Structure

After completion, results are saved to `/var/log/usvf_stress_YYYYMMDD_HHMMSS/`:

```
usvf_stress_YYYYMMDD_HHMMSS/
├── logs/
│   ├── compute_stress.log
│   ├── storage_stress.log
│   ├── network_stress.log
│   ├── memory_stress.log
│   └── monitoring.log
├── raw_data/
│   ├── compute_results.yaml
│   ├── fio_results_*.json
│   ├── network_results_*.json
│   ├── memory_results.yaml
│   ├── telemetry.csv
│   ├── storage_devices.txt
│   ├── network_devices.txt
│   └── lscpu.json
└── reports/
    ├── FINAL_REPORT.txt      # Comprehensive report
    ├── SUMMARY.txt            # Quick summary
    └── hardware_inventory.txt # Detailed hardware list
```

## Report Contents

### Final Report Sections

1. **Test Information**: Date, duration, hostname, kernel version
2. **Hardware Inventory**: Complete component list with models and specifications
3. **CPU/Compute Results**: Operations/second, thermal performance
4. **Storage Results**: Per-device IOPS and bandwidth for all test patterns
5. **Network Results**: Per-interface TCP/UDP throughput
6. **Memory Results**: Operations/second, error counts
7. **Monitoring Summary**: Temperature, fan, power statistics
8. **Unknown Devices**: PCI devices that weren't specifically tested
9. **Test Status Summary**: Pass/fail for each component

### Viewing Reports

```bash
# View the comprehensive report
cat /var/log/usvf_stress_*/reports/FINAL_REPORT.txt

# View quick summary
cat /var/log/usvf_stress_*/reports/SUMMARY.txt

# View real-time telemetry data
cat /var/log/usvf_stress_*/raw_data/telemetry.csv
```

## Requirements

### Operating System
- Ubuntu 24.04 LTS (tested)
- Other Debian-based distributions (should work)
- Root access required

### Automatic Dependencies
The following packages are automatically installed:
- stress-ng (CPU/memory stress)
- fio (storage benchmarking)
- iperf3 (network testing)
- ipmitool (BMC/IPMI access)
- lm-sensors (temperature monitoring)
- smartmontools (disk health)
- nvme-cli (NVMe management)
- ethtool (network interface tools)
- sysstat (system statistics)
- jq, bc (data processing)

## Safety Features

### Thermal Protection
- Continuous temperature monitoring every 5 seconds
- **Automatic emergency shutdown** if CPU temperature exceeds 95°C
- All stress processes terminated immediately on thermal event

### Memory Protection
- Uses only 85% of total system memory to avoid OOM killer
- EDAC monitoring for memory errors
- Alerts on uncorrectable memory errors

### Graceful Cleanup
- Ctrl+C handler to stop all processes cleanly
- Signal traps ensure no orphaned stress processes
- Temporary test files automatically removed

## Advanced Usage

### Modular Architecture

The framework is split into modules in `modules/`:

- `install-deps.sh` - Dependency management
- `hardware-detect.sh` - Hardware discovery
- `compute-stress.sh` - CPU stress testing
- `storage-stress.sh` - Storage benchmarking
- `network-stress.sh` - Network testing
- `memory-stress.sh` - Memory stress
- `monitoring.sh` - Real-time monitoring
- `report-generator.sh` - Report creation

### Customization

You can modify individual modules to:
- Add new stress tests
- Change core distribution percentages
- Adjust thermal thresholds
- Add custom hardware detection
- Modify report formatting

### Storage Testing Notes

- **Non-destructive**: All tests run in /tmp (not on actual disks)
- **Device-specific optimization**: NVMe gets higher queue depth than HDDs
- **Comprehensive patterns**: Sequential read/write, random 4K read/write, mixed workload

### Network Testing Notes

- **Per-interface testing**: Each UP interface tested independently
- **TCP and UDP**: Separate throughput measurements
- **Loopback fallback**: Tests loopback if no external interfaces available
- **Smart NIC detection**: Identifies Mellanox and other advanced NICs

## Troubleshooting

### "Permission denied" errors
**Solution**: Run with `sudo` - root access is required

### No BMC/IPMI data
**Cause**: Server may not have BMC or ipmi_devintf kernel module not loaded
**Solution**: Monitoring continues using lm-sensors; this is not critical

### Storage tests show "No devices"
**Cause**: Normal on systems with only root partition
**Solution**: Tests run on /tmp; not an error

### Network tests fail
**Cause**: No interfaces in UP state or firewall blocking iperf3
**Solution**: Ensure at least one interface is UP; check firewall rules

### Temperature shows 0°C
**Cause**: Sensors not initialized or not available
**Solution**: Run `sensors-detect` manually; framework attempts auto-init

## Performance Impact

### During Testing
- **100% CPU utilization** (by design)
- **High memory usage** (85% of total)
- **Storage I/O saturation** (especially on NVMe)
- **Network bandwidth utilization** (loopback testing)

### Recommendations
- Run during maintenance windows
- Do not run on production systems under load
- Ensure adequate cooling before starting
- Monitor for the first few minutes to verify thermal stability

## Interpreting Results

### CPU Performance
- Higher operations/second = better performance
- Compare across similar CPU models
- Check for thermal throttling in temperature logs

### Storage Performance
- **NVMe**: Expect >500K random read IOPS, >3GB/s sequential
- **SSD**: Expect >50K random read IOPS, >500MB/s sequential  
- **HDD**: Expect <200 random read IOPS, >100MB/s sequential

### Network Performance
- **10GbE**: Expect ~9.4 Gbps TCP throughput
- **1GbE**: Expect ~940 Mbps TCP throughput
- UDP packet loss should be <0.01%

### Memory
- Zero uncorrectable errors expected
- Correctable errors should be minimal (<10 during test)

## Contributing

To extend the framework:

1. Add new modules in `modules/` directory
2. Follow naming convention: `component-action.sh`
3. Export results to `$OUTPUT_DIR/raw_data/`
4. Update `report-generator.sh` to parse new results
5. Update `server-stress.sh` to call new module

## Version History

- **v3.0** (Current): Modular architecture, comprehensive reporting
- **v2.2**: Auto-install, high-density support
- **v1.0**: Initial release

## License

MIT License - Free to use and modify

## Support

For issues or questions:
1. Check logs in `$OUTPUT_DIR/logs/`
2. Review hardware_inventory.txt for detection issues
3. Verify all dependencies installed successfully

## Author

USVF Development Team

---

**⚠️ WARNING**: This framework is designed to stress test servers to their absolute limits. Only run on systems you are authorized to test, and ensure adequate cooling and monitoring are in place.
