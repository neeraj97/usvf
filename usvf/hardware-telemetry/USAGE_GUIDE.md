# Hardware Telemetry System - Usage Guide

Comprehensive guide for configuring and using the Hardware Telemetry System.

## Table of Contents

1. [Installation](#installation)
2. [Basic Usage](#basic-usage)
3. [Configuration](#configuration)
4. [Module-Specific Settings](#module-specific-settings)
5. [Advanced Usage](#advanced-usage)
6. [Output Formats](#output-formats)
7. [Automation](#automation)
8. [Monitoring Integration](#monitoring-integration)
9. [Troubleshooting](#troubleshooting)
10. [Examples](#examples)

---

## Installation

### Step 1: Navigate to Directory

```bash
cd /path/to/usvf/hardware-telemetry
```

### Step 2: Make Scripts Executable

```bash
chmod +x telemetry-collector.sh
chmod +x modules/*.sh
```

### Step 3: Install Dependencies

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y \
    lm-sensors smartmontools sysstat \
    ethtool ipmitool nvme-cli hdparm \
    pciutils usbutils dmidecode numactl \
    linux-tools-generic bc
```

**RHEL/CentOS/Rocky:**
```bash
sudo yum install -y \
    lm_sensors smartmontools sysstat \
    ethtool ipmitool nvme-cli hdparm \
    pciutils usbutils dmidecode numactl \
    perf bc
```

### Step 4: Initialize Sensors (First Time)

```bash
sudo sensors-detect --auto
```

### Step 5: Test Installation

```bash
sudo ./telemetry-collector.sh --once
```

---

## Basic Usage

### Run Single Collection

Collect telemetry once and exit:

```bash
sudo ./telemetry-collector.sh --once
```

**Output:**
- `data/telemetry_YYYYMMDD_HHMMSS.txt` - Human-readable format
- `data/telemetry_YYYYMMDD_HHMMSS.json` - JSON format
- `logs/telemetry_YYYYMMDD.log` - Operation log

### Run Multiple Collections

Collect telemetry N times at configured intervals:

```bash
# Collect 10 samples
sudo ./telemetry-collector.sh --count 10

# Collect 100 samples (useful for longer monitoring)
sudo ./telemetry-collector.sh --count 100
```

### Run Continuous Collection

Run indefinitely at configured intervals (Ctrl+C to stop):

```bash
sudo ./telemetry-collector.sh
```

### View Help

```bash
./telemetry-collector.sh --help
```

---

## Configuration

Edit `config/telemetry.conf` to customize behavior.

### Global Settings

```bash
# Collection interval in seconds (default: 300 = 5 minutes)
COLLECTION_INTERVAL=300

# Output directories
OUTPUT_DIR="data"
LOG_DIR="logs"

# Enable JSON output (in addition to text)
ENABLE_JSON_OUTPUT=true

# Require root privileges
REQUIRE_ROOT=true
```

### File Rotation

```bash
# Enable automatic file rotation
ENABLE_FILE_ROTATION=true

# Maximum number of files to keep (0 = unlimited)
MAX_FILES_TO_KEEP=100

# Maximum age in days (0 = unlimited)
MAX_FILE_AGE_DAYS=30
```

### Module Enablement

Enable or disable entire modules:

```bash
ENABLE_CPU_TELEMETRY=true
ENABLE_MEMORY_TELEMETRY=true
ENABLE_STORAGE_TELEMETRY=true
ENABLE_NETWORK_TELEMETRY=true
ENABLE_GPU_TELEMETRY=true
ENABLE_MOTHERBOARD_TELEMETRY=true
ENABLE_THERMAL_TELEMETRY=true
ENABLE_POWER_TELEMETRY=true
ENABLE_PCIE_TELEMETRY=true
ENABLE_USB_TELEMETRY=true
ENABLE_RAID_TELEMETRY=true
ENABLE_BMC_TELEMETRY=true
```

---

## Module-Specific Settings

### CPU Telemetry

```bash
# Collect CPU frequency information
CPU_COLLECT_FREQUENCY=true

# Collect CPU temperature
CPU_COLLECT_TEMPERATURE=true

# Collect cache statistics
CPU_COLLECT_CACHE_STATS=true

# Collect throttling events
CPU_COLLECT_THROTTLING=true

# Collect power consumption (requires RAPL support)
CPU_COLLECT_POWER=true
```

**Example Use Cases:**
- **Performance Tuning**: Enable frequency and cache stats
- **Thermal Monitoring**: Enable temperature and throttling
- **Power Optimization**: Enable power collection

### Memory Telemetry

```bash
# Collect per-DIMM information
MEMORY_COLLECT_PER_DIMM=true

# Collect memory errors (ECC)
MEMORY_COLLECT_ERRORS=true

# Collect memory bandwidth (requires tools)
MEMORY_COLLECT_BANDWIDTH=true

# Collect memory temperature
MEMORY_COLLECT_TEMPERATURE=true
```

**Example Use Cases:**
- **Capacity Planning**: Monitor usage patterns
- **Reliability**: Track ECC errors
- **Performance**: Analyze bandwidth utilization

### Storage Telemetry

```bash
# Collect SMART data
STORAGE_COLLECT_SMART=true

# Collect temperature
STORAGE_COLLECT_TEMPERATURE=true

# Collect wear level (SSD)
STORAGE_COLLECT_WEAR_LEVEL=true

# Collect TRIM status (SSD)
STORAGE_COLLECT_TRIM_STATUS=true

# Collect I/O statistics
STORAGE_COLLECT_IO_STATS=true

# Collect NVMe-specific health data
STORAGE_COLLECT_NVME_HEALTH=true

# Alert thresholds
ALERT_STORAGE_WEAR_WARNING=20  # Warn at 20% remaining
ALERT_STORAGE_WEAR_CRITICAL=10  # Critical at 10% remaining
```

**Example Use Cases:**
- **Predictive Maintenance**: Monitor SMART and wear levels
- **Performance Analysis**: Track I/O patterns
- **SSD Optimization**: Monitor TRIM status

### Network Telemetry

```bash
# Collect link status
NETWORK_COLLECT_LINK_STATUS=true

# Collect bandwidth statistics
NETWORK_COLLECT_BANDWIDTH=true

# Collect errors
NETWORK_COLLECT_ERRORS=true

# Collect packet drops
NETWORK_COLLECT_DROPS=true

# Collect queue statistics
NETWORK_COLLECT_QUEUE_STATS=true

# Collect NIC temperature
NETWORK_COLLECT_TEMPERATURE=true

# Alert thresholds
ALERT_NETWORK_ERRORS_THRESHOLD=1000
ALERT_NETWORK_DROPS_THRESHOLD=1000
```

**Example Use Cases:**
- **Network Troubleshooting**: Monitor errors and drops
- **Capacity Planning**: Track bandwidth utilization
- **Performance Tuning**: Analyze queue depths

### GPU Telemetry

```bash
# Collect GPU temperature
GPU_COLLECT_TEMPERATURE=true

# Collect GPU usage
GPU_COLLECT_USAGE=true

# Collect GPU memory
GPU_COLLECT_MEMORY=true

# Collect power consumption
GPU_COLLECT_POWER=true

# Collect fan speed
GPU_COLLECT_FAN_SPEED=true

# Collect clock speeds
GPU_COLLECT_CLOCK_SPEED=true
```

**Example Use Cases:**
- **ML/AI Workloads**: Monitor GPU utilization and memory
- **Gaming Servers**: Track temperature and fan speeds
- **Power Management**: Monitor power consumption

### System Telemetry

#### Thermal Sensors

```bash
# Collect all thermal sensors
THERMAL_COLLECT_ALL_SENSORS=true

# Alert threshold (°C)
THERMAL_ALERT_THRESHOLD=80
```

#### Power Management

```bash
# Collect power consumption
POWER_COLLECT_CONSUMPTION=true

# Collect PSU status (via IPMI)
POWER_COLLECT_PSU_STATUS=true

# Collect battery status (laptops/UPS)
POWER_COLLECT_BATTERY=true
```

#### PCIe Devices

```bash
# Collect PCIe link status
PCIE_COLLECT_LINK_STATUS=true
```

#### RAID Controllers

```bash
# Collect array status
RAID_COLLECT_ARRAY_STATUS=true

# Collect physical disk health
RAID_COLLECT_DISK_HEALTH=true
```

#### BMC/IPMI

```bash
# Collect BMC sensors
BMC_COLLECT_SENSORS=true

# Collect System Event Log
BMC_COLLECT_SEL=true

# Collect FRU information
BMC_COLLECT_FRU=true
```

---

## Advanced Usage

### Custom Collection Intervals

Create a wrapper script for different intervals:

```bash
#!/bin/bash
# fast-telemetry.sh - Collect every 60 seconds

sed -i 's/COLLECTION_INTERVAL=.*/COLLECTION_INTERVAL=60/' config/telemetry.conf
sudo ./telemetry-collector.sh --count 60
sed -i 's/COLLECTION_INTERVAL=.*/COLLECTION_INTERVAL=300/' config/telemetry.conf
```

### Selective Module Collection

Create configuration profiles:

```bash
# Profile: storage-focus.conf
# Copy and modify telemetry.conf
cp config/telemetry.conf config/storage-focus.conf

# Edit to enable only storage-related modules
# Then use: CONFIG_FILE=config/storage-focus.conf ./telemetry-collector.sh
```

### Background Execution

Run as background service:

```bash
# Using nohup
nohup sudo ./telemetry-collector.sh > /dev/null 2>&1 &

# Save PID
echo $! > telemetry.pid

# Stop later
kill $(cat telemetry.pid)
```

### Systemd Service

Create `/etc/systemd/system/hardware-telemetry.service`:

```ini
[Unit]
Description=Hardware Telemetry Collector
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/path/to/usvf/hardware-telemetry
ExecStart=/path/to/usvf/hardware-telemetry/telemetry-collector.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable hardware-telemetry
sudo systemctl start hardware-telemetry
sudo systemctl status hardware-telemetry
```

---

## Output Formats

### Text Output Format

```
===== Hardware Telemetry =====
Timestamp: 2026-10-01 22:00:00
Hostname: server01
==========

=== CPU ===
Model: Intel Xeon Gold 6248R
Cores: 48
Threads: 96
Temperature: 42°C
Usage: 23.5%
...

=== Memory ===
Total: 256GB
Used: 128GB (50%)
...
```

### JSON Output Format

```json
{
  "timestamp": "2026-10-01T22:00:00+05:30",
  "hostname": "server01",
  "modules": {
    "cpu": {
      "model": "Intel Xeon Gold 6248R",
      "cores": 48,
      "threads": 96,
      "temperature_celsius": 42,
      "usage_percent": 23.5
    },
    "memory": {
      "total_gb": 256,
      "used_gb": 128,
      "used_percent": 50
    }
  }
}
```

### Parsing JSON Output

```bash
# Extract CPU temperature using jq
jq '.modules.cpu.temperature_celsius' data/telemetry_*.json

# Get storage devices
jq '.modules.storage.devices[] | {device, temperature_celsius}' data/telemetry_*.json

# Find high memory usage
jq 'select(.modules.memory.used_percent > 80)' data/telemetry_*.json
```

---

## Automation

### Cron Job

Add to crontab for periodic execution:

```bash
# Edit crontab
sudo crontab -e

# Run every 5 minutes
*/5 * * * * /path/to/usvf/hardware-telemetry/telemetry-collector.sh --once

# Run hourly
0 * * * * /path/to/usvf/hardware-telemetry/telemetry-collector.sh --once

# Run daily at 2 AM
0 2 * * * /path/to/usvf/hardware-telemetry/telemetry-collector.sh --once
```

### Scheduled Tasks

Create automated reports:

```bash
#!/bin/bash
# daily-report.sh

# Collect telemetry
sudo /path/to/usvf/hardware-telemetry/telemetry-collector.sh --once

# Generate summary
LATEST=$(ls -t data/telemetry_*.json | head -1)
jq '{
  timestamp: .timestamp,
  cpu_temp: .modules.cpu.temperature_celsius,
  mem_usage: .modules.memory.used_percent,
  disk_health: .modules.storage.devices[].smart_health
}' "$LATEST" > daily-summary.json

# Email report (configure mail settings)
mail -s "Hardware Telemetry Report" admin@example.com < daily-summary.json
```

---

## Monitoring Integration

### Prometheus Export

Convert JSON to Prometheus format:

```bash
#!/bin/bash
# prometheus-exporter.sh

LATEST=$(ls -t data/telemetry_*.json | head -1)

# Export metrics
echo "# HELP hardware_cpu_temperature_celsius CPU Temperature"
echo "# TYPE hardware_cpu_temperature_celsius gauge"
jq -r '.modules.cpu.temperature_celsius | "hardware_cpu_temperature_celsius \(.)"' "$LATEST"

echo "# HELP hardware_memory_used_percent Memory Usage"
echo "# TYPE hardware_memory_used_percent gauge"
jq -r '.modules.memory.used_percent | "hardware_memory_used_percent \(.)"' "$LATEST"
```

### Grafana Dashboard

Use JSON output with Grafana's JSON API datasource or convert to InfluxDB format.

### ELK Stack

Forward JSON logs to Elasticsearch:

```bash
# Using Filebeat
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /path/to/usvf/hardware-telemetry/data/telemetry_*.json
  json.keys_under_root: true
```

---

## Troubleshooting

### Issue: Missing SMART Data

**Cause**: smartctl not installed or insufficient permissions

**Solution**:
```bash
sudo apt-get install smartmontools
sudo smartctl -i /dev/sda  # Test manually
```

### Issue: No Temperature Sensors

**Cause**: lm-sensors not configured

**Solution**:
```bash
sudo sensors-detect --auto
sudo systemctl restart lm-sensors
sensors  # Verify output
```

### Issue: High Disk Usage

**Cause**: Too many telemetry files

**Solution**:
```bash
# Enable rotation in config
ENABLE_FILE_ROTATION=true
MAX_FILES_TO_KEEP=50
MAX_FILE_AGE_DAYS=7

# Manual cleanup
find data/ -name "telemetry_*.txt" -mtime +7 -delete
find data/ -name "telemetry_*.json" -mtime +7 -delete
```

### Issue: Permission Denied

**Cause**: Not running as root

**Solution**:
```bash
sudo ./telemetry-collector.sh --once
```

### Issue: Module Not Collecting Data

**Cause**: Required tool not installed

**Solution**:
```bash
# Check logs
tail -f logs/telemetry_*.log

# Verify tool availability
which nvidia-smi  # For GPU
which ipmitool    # For BMC
```

---

## Examples

### Example 1: Monitor Server During Stress Test

```bash
# Start continuous telemetry (60-second intervals)
sed -i 's/COLLECTION_INTERVAL=.*/COLLECTION_INTERVAL=60/' config/telemetry.conf
sudo ./telemetry-collector.sh &
TELEM_PID=$!

# Run stress test
stress-ng --cpu 96 --timeout 3600

# Stop telemetry
kill $TELEM_PID

# Analyze results
jq '.modules.cpu | {temp: .temperature_celsius, usage: .usage_percent}' data/telemetry_*.json
```

### Example 2: Storage Health Check

```bash
# Enable all storage metrics
sed -i 's/STORAGE_COLLECT_.*/STORAGE_COLLECT_\1=true/' config/telemetry.conf

# Run single collection
sudo ./telemetry-collector.sh --once

# Check SMART status
LATEST=$(ls -t data/telemetry_*.json | head -1)
jq '.modules.storage.devices[] | select(.smart_health != "PASSED")' "$LATEST"
```

### Example 3: Network Performance Analysis

```bash
# Collect network stats every 30 seconds for 10 minutes
sed -i 's/COLLECTION_INTERVAL=.*/COLLECTION_INTERVAL=30/' config/telemetry.conf
sudo ./telemetry-collector.sh --count 20

# Analyze drops and errors
for file in data/telemetry_*.json; do
  echo "File: $file"
  jq '.modules.network.interfaces[] | select(.rx_dropped > 0 or .tx_dropped > 0)' "$file"
done
```

### Example 4: Temperature Monitoring

```bash
# Monitor temperatures across all components
jq '{
  timestamp: .timestamp,
  cpu_temp: .modules.cpu.temperature.package_celsius,
  storage_temps: [.modules.storage.devices[].temperature_celsius],
  gpu_temp: .modules.gpu.gpus[].temperature_celsius,
  sensors: .modules.system.thermal.sensors
}' data/telemetry_*.json
```

---

## Best Practices

1. **Start with defaults** - Use default configuration initially
2. **Monitor disk space** - Enable file rotation early
3. **Test before production** - Run `--once` to verify
4. **Use JSON for automation** - Easier to parse than text
5. **Regular maintenance** - Review and clean logs periodically
6. **Document changes** - Keep notes on configuration modifications
7. **Backup configs** - Save working configurations
8. **Monitor the monitor** - Check telemetry collector health

---

## Support and Feedback

For issues, feature requests, or contributions, please refer to the main USVF project documentation.

---

**Version**: 1.0.0  
**Last Updated**: 2026-10-01
