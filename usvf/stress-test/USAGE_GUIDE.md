# USVF Usage Guide

## Quick Reference

### Basic Commands

```bash
# Navigate to the stress-test directory
cd usvf/stress-test

# Run with default settings (10 minutes)
sudo ./server-stress.sh

# Run for 30 minutes
sudo ./server-stress.sh 1800

# Run for 1 hour
sudo ./server-stress.sh 3600
```

## What Gets Tested

### 1. CPU/Compute (40% of cores)
- Matrix multiplication (generates maximum heat)
- FFT (Fast Fourier Transform)
- Ackermann function (floating-point intensive)

### 2. Storage (30% of cores)
For each detected device (NVMe/SSD/HDD):
- Sequential read/write (1MB blocks)
- Random read/write (4K blocks)
- Mixed workload (70% read, 30% write)

### 3. Network (20% of cores)
For each UP network interface:
- TCP throughput test
- UDP throughput test with packet loss measurement
- Interface statistics collection

### 4. Memory (10% of cores)
- Data integrity verification (85% of total RAM)
- Memory bandwidth testing
- Cache latency testing
- EDAC error monitoring

### 5. Real-time Monitoring (Every 5 seconds)
- CPU temperature (average and peak)
- Fan speeds
- Power consumption
- Memory errors
- CPU and memory utilization
- Disk I/O rates

## Understanding the Output

### During Testing

You'll see a live dashboard like this:
```
[2026-01-06 17:45:23] Temp: 72.5°C (Max: 78.0°C) | Fan: 4500 RPM | Power: 250W | Mem Err: 0/0 | CPU: 98% | Mem: 82%
```

**What it means:**
- `Temp`: Average CPU temperature across all cores
- `Max`: Highest temperature recorded on any core
- `Fan`: Average fan speed across all fans
- `Power`: Current power consumption in Watts
- `Mem Err`: Correctable/Uncorrectable memory errors
- `CPU`: CPU utilization percentage
- `Mem`: Memory usage percentage

### After Testing

Results are saved to `/var/log/usvf_stress_YYYYMMDD_HHMMSS/`

**Key Files:**

1. **reports/FINAL_REPORT.txt** - Complete test results
2. **reports/SUMMARY.txt** - Quick overview
3. **reports/hardware_inventory.txt** - All detected hardware
4. **raw_data/telemetry.csv** - Full monitoring data (import to Excel/Grafana)

## Example Report Interpretation

### CPU Results
```
Total Operations: 1234567890
Operations/Second: 2057613
Status: COMPLETED
```
✓ Higher ops/second = better performance
✓ Compare against baseline or similar systems

### Storage Results
```
Device: /dev/nvme0n1
Model: Samsung SSD 980 PRO 1TB
Type: NVMe

Sequential Read (1M):    3500000 KB/s    3400 IOPS
Sequential Write (1M):   3000000 KB/s    2900 IOPS
Random Read (4K):        180000 KB/s     450000 IOPS
Random Write (4K):       150000 KB/s     375000 IOPS
```
✓ NVMe should show >3GB/s sequential, >400K random IOPS
✓ Check if results match manufacturer specs

### Network Results
```
Interface: eth0
TCP Throughput: 9.42 Gbps
UDP Throughput: 9.38 Gbps
UDP Packet Loss: 0.02%
```
✓ 10GbE should achieve ~9.4 Gbps
✓ Packet loss should be <0.1%

### Memory Results
```
Correctable Errors: 0
Uncorrectable Errors: 0
```
✓ Zero uncorrectable errors is expected
✓ >10 correctable errors may indicate bad RAM

## Thermal Safety

The framework includes automatic thermal protection:

- Monitors temperature every 5 seconds
- **Automatic shutdown at 95°C**
- All tests terminated immediately
- Results saved before shutdown

## Common Scenarios

### Scenario 1: New Server Validation
```bash
# Run for 1 hour to ensure stability
sudo ./server-stress.sh 3600

# Check the report for:
# - All hardware detected correctly
# - No thermal throttling
# - No memory errors
# - Performance meets expectations
```

### Scenario 2: Before Production Deployment
```bash
# Run for 4 hours (overnight test)
sudo ./server-stress.sh 14400

# Review telemetry.csv for:
# - Temperature stability over time
# - Power consumption patterns
# - No degradation in performance
```

### Scenario 3: Quick Health Check
```bash
# Run for 5 minutes
sudo ./server-stress.sh 300

# Quick check for:
# - System can handle full load
# - No immediate hardware issues
# - Cooling is adequate
```

## Customization Examples

### Change Core Distribution

Edit `server-stress.sh`:
```bash
# Default distribution
COMPUTE_CORES=$((TOTAL_CORES * 40 / 100))  # 40%
STORAGE_CORES=$((TOTAL_CORES * 30 / 100))  # 30%
NETWORK_CORES=$((TOTAL_CORES * 20 / 100))  # 20%
MEMORY_CORES=$((TOTAL_CORES * 10 / 100))   # 10%

# Example: Focus on storage testing
COMPUTE_CORES=$((TOTAL_CORES * 20 / 100))  # 20%
STORAGE_CORES=$((TOTAL_CORES * 50 / 100))  # 50%
NETWORK_CORES=$((TOTAL_CORES * 20 / 100))  # 20%
MEMORY_CORES=$((TOTAL_CORES * 10 / 100))   # 10%
```

### Adjust Thermal Threshold

Edit `modules/monitoring.sh`:
```bash
# Default: 95°C
local THERMAL_LIMIT=95

# More conservative: 85°C
local THERMAL_LIMIT=85
```

### Add Custom Hardware Detection

Edit `modules/hardware-detect.sh` to add detection for specialized hardware.

## Troubleshooting Tips

### Problem: High temperatures immediately
**Solution:** 
- Check cooling system is working
- Verify thermal paste is properly applied
- Ensure adequate airflow
- Consider reducing test duration initially

### Problem: Tests complete but some show FAILED
**Check:**
1. `logs/` directory for error messages
2. Specific component may not be present (normal for some tests)
3. Network interfaces might be DOWN (expected)

### Problem: Low performance numbers
**Investigate:**
- Check for thermal throttling in temperature logs
- Verify BIOS settings (Turbo Boost, C-States)
- Check if power management is limiting performance
- Compare telemetry to identify bottlenecks

### Problem: Memory errors detected
**Action:**
- **Uncorrectable errors**: Replace RAM immediately
- **Correctable errors**: Monitor over time, may indicate failing DIMM

## Data Analysis

### Import Telemetry to Excel/LibreCalc

```bash
# Copy telemetry CSV to your workstation
scp user@server:/var/log/usvf_stress_*/raw_data/telemetry.csv .

# Open in Excel/LibreCalc
# Create charts for:
# - Temperature over time
# - Power consumption trends
# - Memory error accumulation
```

### Grafana Integration

The telemetry.csv can be imported into Grafana for visualization:
- Temperature trends
- Power consumption graphs
- Real-time monitoring dashboards

## Best Practices

1. **Baseline First**: Run on known-good hardware to establish baseline
2. **Document Results**: Keep reports for comparison over time
3. **Scheduled Testing**: Run quarterly to detect degradation
4. **Before Major Changes**: Test before firmware updates or hardware changes
5. **Burn-in New Hardware**: Run 24-48 hour tests on new servers

## Safety Checklist

Before running stress tests:

- [ ] Ensure adequate cooling/airflow
- [ ] Verify server is not in production
- [ ] Check thermal paste is recent (<2 years)
- [ ] Confirm fans are operational
- [ ] Have monitoring access (BMC/IPMI) ready
- [ ] Inform team about maintenance window
- [ ] Have backup plan if hardware fails

## Getting Help

If you encounter issues:

1. Check the logs in `$OUTPUT_DIR/logs/`
2. Review hardware_inventory.txt for detection issues
3. Verify dependencies installed: `dpkg -l | grep -E "stress-ng|fio|iperf3"`
4. Run individual modules manually for debugging
5. Check system logs: `dmesg` and `/var/log/syslog`

## Files Reference

| File | Purpose |
|------|---------|
| server-stress.sh | Main orchestration script |
| modules/install-deps.sh | Install required packages |
| modules/hardware-detect.sh | Detect all hardware |
| modules/compute-stress.sh | CPU stress testing |
| modules/storage-stress.sh | Storage benchmarking |
| modules/network-stress.sh | Network testing |
| modules/memory-stress.sh | Memory stress |
| modules/monitoring.sh | Real-time monitoring |
| modules/report-generator.sh | Create reports |

---

**Remember:** This framework pushes hardware to absolute limits. Use responsibly and only on systems you're authorized to test!
