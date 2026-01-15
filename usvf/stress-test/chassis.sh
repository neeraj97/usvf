#!/bin/bash
# USVF: Unified Server Validation Framework
# Version 2.2 - High-Density Edition (Auto-Install Enabled)

# --- Configuration & Safety Defaults ---
DURATION="300" # Duration in seconds (default 5 mins)
OUTPUT_DIR="/var/log/usvf_stress_$(date +%Y%m%d_%H%M%S)"
IPMI_INTERVAL=5
# Target local loopback if no external IP provided
TARGET_NET_IP=${1:-"127.0.0.1"}

# Ensure Root Access for installation and stress-ng OOM adjustments
if; then
  echo "[-] Critical: Please run as root."
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
PID_LIST=""

# --- Cleanup Trap Function ---
# Ensures no stress processes are left running if script is interrupted
cleanup() {
    echo -e "\n[!] Signal Received. Terminating background stress processes..."
    if; then
        kill $PID_LIST 2>/dev/null
    fi
    # Force kill patterns as safety net
    pkill -f stress-ng
    pkill -f fio
    pkill -f iperf3
    echo "[!] Cleanup complete. Data saved in $OUTPUT_DIR"
}
trap cleanup SIGINT SIGTERM EXIT

# --- Phase 0: Dependency Check & Installation (Ubuntu 24.04) ---
echo "[-] Phase 0: Checking and installing dependencies..."

# Define the list of required tools for this framework
REQUIRED_PKGS="stress-ng fio iperf3 ipmitool lshw dmidecode nvme-cli edac-utils jq"

# Update package lists and install missing tools
echo "[i] Updating apt repositories..."
apt-get update -qq

echo "[i] Installing required packages: $REQUIRED_PKGS"
# DEBIAN_FRONTEND=noninteractive prevents prompts during install
DEBIAN_FRONTEND=noninteractive apt-get install -y $REQUIRED_PKGS

if [ $? -ne 0 ]; then
    echo "[!] Error: Failed to install dependencies. Check your internet connection or apt configuration."
    exit 1
fi
echo "[+] Dependencies verified."


# --- Phase 1: Inventory Discovery ---
echo "[-] Phase 1: Hardware Topology Discovery..."
lscpu -J > "$OUTPUT_DIR/cpu_topology.json"
lsblk -J -o NAME,SIZE,TYPE,ROTA,MOUNTPOINT > "$OUTPUT_DIR/storage_topology.json"
ipmitool sdr list full > "$OUTPUT_DIR/sensors_baseline.csv"
echo "[+] Topology mapped."

# Dynamic Parameter Calculation
CPU_CORES=$(nproc)
# Calculate 85% of RAM in bytes for stress-ng to avoid OOM Killer
MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_STRESS_BYTES=$(($MEM_TOTAL_KB * 85 / 100 * 1024))

echo "[i] Configuration:"
echo "    CPU Workers: $CPU_CORES"
echo "    Mem Target : $(($MEM_STRESS_BYTES / 1024 / 1024 / 1024)) GB"
echo "    Duration   : $DURATION seconds"

# --- Phase 2: Launching Concurrent Stressors ---

# 2.1 Compute & Memory (stress-ng)
# Uses matrixprod for heat, vm for memory integrity, switch for scheduler
echo "[-] Launching Compute/Memory Stress (stress-ng)..."
stress-ng \
    --cpu "$CPU_CORES" --cpu-method matrixprod \
    --vm 2 --vm-bytes 4G --vm-method all --verify \
    --switch 4 \
    --timeout "$DURATION" \
    --metrics-brief --tz \
    --yaml "$OUTPUT_DIR/stress_ng_results.yaml" &
PID_STRESS=$!
PID_LIST="$PID_LIST $PID_STRESS"
echo "[+] stress-ng PID: $PID_STRESS"

# 2.2 Storage I/O (fio)
echo "[-] Launching Storage Stress (fio)..."
# Create dynamic Job File for reproducibility
cat <<EOF > "$OUTPUT_DIR/stress_job.fio"
[global]
ioengine=libaio
direct=1
gtod_reduce=1
group_reporting
time_based
runtime=$DURATION
[random-rw-load]
rw=randrw
rwmixread=70
bs=4k
size=4G
numjobs=4
iodepth=64
directory=/tmp
EOF

fio --output-format=json --output="$OUTPUT_DIR/fio_results.json" "$OUTPUT_DIR/stress_job.fio" &
PID_FIO=$!
PID_LIST="$PID_LIST $PID_FIO"
echo "[+] fio PID: $PID_FIO"

# 2.3 Network Stress (iperf3)
echo "[-] Launching Network Stress (iperf3) -> $TARGET_NET_IP..."
iperf3 -c "$TARGET_NET_IP" -t "$DURATION" -J --logfile "$OUTPUT_DIR/iperf_results.json" &
PID_NET=$!
PID_LIST="$PID_LIST $PID_NET"
echo "[+] iperf3 PID: $PID_NET"

# --- Phase 3: The Monitoring Control Loop ---
echo "[-] Phase 3: Real-time Telemetry & Safety Loop..."
echo "Timestamp,CPU_Temp,Fan_Speed,Power_Watts,EDAC_CE,EDAC_UE" > "$OUTPUT_DIR/telemetry_log.csv"

START_TIME=$(date +%s)
END_TIME=$(($START_TIME + $DURATION))

while; do
    TS=$(date +%H:%M:%S)
    
    # 3.1 IPMI Sensor Extraction (Heuristic Parsing)
    # Dump all sensors to temp
    ipmitool sdr list full > /tmp/ipmi_snapshot.txt
    
    # Extract Average CPU Temp (Looking for patterns like 'CPU Temp', 'Pkg Temp', 'Temp_CPU')
    CPU_TEMP=$(grep -i "Temp" /tmp/ipmi_snapshot.txt | grep -E "CPU|Pkg" | awk '{sum+=$2; count++} END {if (count > 0) print sum/count; else print "0"}')
    
    # Extract Average Fan Speed (Ignoring stopped fans 0 RPM)
    FAN_SPEED=$(grep -i "Fan" /tmp/ipmi_snapshot.txt | grep "RPM" | grep -v "0 RPM" | awk '{sum+=$2; count++} END {if (count > 0) print sum/count; else print "0"}')
    
    # Extract Power Draw
    POWER=$(ipmitool dcmi power reading 2>/dev/null | grep "Instantaneous" | awk '{print $4}')
    && POWER="0"

    # 3.2 EDAC Error Counters (Kernel Memory Monitoring)
    # Summing all Correctable Errors across all memory controllers
    EDAC_CE=$(cat /sys/devices/system/edac/mc/mc*/ce_count 2>/dev/null | awk '{s+=$1} END {print s}')
    && EDAC_CE="0"
    
    # Summing Uncorrectable Errors (Critical)
    EDAC_UE=$(cat /sys/devices/system/edac/mc/mc*/ue_count 2>/dev/null | awk '{s+=$1} END {print s}')
    && EDAC_UE="0"

    # 3.3 Log and Display
    echo "$TS,$CPU_TEMP,$FAN_SPEED,$POWER,$EDAC_CE,$EDAC_UE" >> "$OUTPUT_DIR/telemetry_log.csv"
    
    # Live Dashboard
    echo -ne "Status: RUNNING | Temp: ${CPU_TEMP}C | Fan: ${FAN_SPEED} RPM | Power: ${POWER}W | MEM Err (CE/UE): ${EDAC_CE}/${EDAC_UE}\r"
    
    # 3.4 Safety Cutoff (Thermal Runaway Protection)
    # If Temp > 95C, Abort immediately to save hardware
    if; then
        echo -e "\n[!!!] CRITICAL THERMAL EVENT: CPU > 95C. ABORTING TEST."
        kill $PID_LIST
        break
    fi

    sleep $IPMI_INTERVAL
done

echo -e "\n[+] Stress duration complete. Waiting for processes to exit..."
wait $PID_STRESS $PID_FIO $PID_NET
echo "[+] Test Complete. Results ready for Python processing."