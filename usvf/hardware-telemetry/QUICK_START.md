# Hardware Telemetry - Quick Start Guide

## 🚀 Quick Start (1 Minute)

```bash
cd usvf/hardware-telemetry

# Run single collection
sudo ./telemetry-collector.sh --once

# View results
ls -lh data/
cat data/telemetry_*.txt
```

## 📊 What Gets Monitored

### CPU
- Temperature, frequency, throttling
- Cache statistics
- Power consumption
- Per-core usage

### Memory
- Usage, errors (ECC)
- Per-DIMM information
- NUMA statistics
- Bandwidth

### Storage (SSD/HDD/NVMe)
- SMART data & health
- Temperature
- **Wear level & remaining life**
- **TRIM status & requirements**
- I/O statistics
- Read/write errors

### Network (NICs)
- **Bandwidth utilization**
- **Packet drops & errors**
- Link status & speed
- Temperature
- Queue statistics

### GPU (NVIDIA/AMD/Intel)
- Temperature
- Usage & memory
- Power consumption
- Fan speed
- Clock speeds

### System Components
- **Motherboard & BIOS info**
- **All thermal sensors**
- **Power consumption (PSU, battery)**
- **PCIe devices & link status**
- **USB devices**
- **RAID controllers & arrays**
- **BMC/IPMI sensors**

## 📁 File Structure

```
hardware-telemetry/
├── telemetry-collector.sh    # Main script
├── config/telemetry.conf      # Configuration
├── modules/                   # Telemetry modules
├── data/                      # Output files
├── logs/                      # Log files
├── README.md                  # Full documentation
├── USAGE_GUIDE.md            # Detailed guide
└── QUICK_START.md            # This file
```

## 🔧 Common Commands

```bash
# Single collection
sudo ./telemetry-collector.sh --once

# Collect 10 samples at configured interval (default: 5 minutes)
sudo ./telemetry-collector.sh --count 10

# Continuous monitoring (Ctrl+C to stop)
sudo ./telemetry-collector.sh

# View help
./telemetry-collector.sh --help
```

## ⚙️ Quick Configuration

Edit `config/telemetry.conf`:

```bash
# Change collection interval (seconds)
COLLECTION_INTERVAL=300  # 5 minutes (default)
COLLECTION_INTERVAL=60   # 1 minute (fast)
COLLECTION_INTERVAL=900  # 15 minutes (slow)

# Enable/disable modules
ENABLE_CPU_TELEMETRY=true
ENABLE_STORAGE_TELEMETRY=true
ENABLE_NETWORK_TELEMETRY=true
# ... etc
```

## 📤 Output Files

### Text Format
`data/telemetry_20261001_220000.txt`
- Human-readable
- Easy to view/analyze
- Great for quick checks

### JSON Format
`data/telemetry_20261001_220000.json`
- Machine-readable
- Easy to parse
- Integration-ready

## 🔍 Viewing Results

```bash
# View latest text file
cat data/telemetry_*.txt | tail -100

# View latest JSON (requires jq)
jq '.' data/telemetry_*.json | head -50

# Check storage health
jq '.modules.storage.devices[] | {device, smart_health, temperature_celsius}' data/telemetry_*.json

# Check network stats
jq '.modules.network.interfaces[] | {name, rx_dropped, tx_dropped}' data/telemetry_*.json
```

## 📋 System Requirements

**Required:**
- Linux OS
- bash, lscpu, free, lsblk, ip, bc

**Recommended for full telemetry:**
- smartmontools (storage SMART data)
- lm-sensors (temperature sensors)
- dmidecode (motherboard info)
- ethtool (network details)
- nvidia-smi (NVIDIA GPUs)

**Install on Ubuntu/Debian:**
```bash
sudo apt-get install -y lm-sensors smartmontools sysstat \
    ethtool ipmitool nvme-cli dmidecode pciutils usbutils
```

## 🎯 Use Cases

1. **Health Monitoring**: Track hardware health over time
2. **Predictive Maintenance**: Identify failing components early
3. **Performance Tuning**: Find bottlenecks and optimize
4. **Capacity Planning**: Monitor resource utilization trends
5. **Troubleshooting**: Capture detailed hardware state

## 📖 Documentation

- **README.md** - Overview and features
- **USAGE_GUIDE.md** - Complete configuration guide
- **QUICK_START.md** - This file

## ⚠️ Important Notes

- **Run with sudo** for complete telemetry access
- **Monitor disk space** - Enable file rotation in config
- **Check logs** - Located in `logs/` directory
- **Test first** - Run `--once` before continuous monitoring

## 🆘 Troubleshooting

**Missing data?**
- Check if required tools are installed
- Verify running with sudo
- Review logs in `logs/` directory

**High disk usage?**
- Enable file rotation in config
- Reduce MAX_FILES_TO_KEEP

**Need help?**
- See README.md for full documentation
- See USAGE_GUIDE.md for detailed examples

---

**Version**: 1.0.0  
**Created**: 2026-10-01
