#!/bin/bash
# USVF: Unified Server Validation Framework
# Version 3.0 - Comprehensive Server Stress Testing
# Main Orchestration Script

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"
DURATION="${1:-600}"  # Default 10 minutes
OUTPUT_DIR="/var/log/usvf_stress_$(date +%Y%m%d_%H%M%S)"
INTERACTIVE="${2:-yes}"  # Interactive mode for unknown devices

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Root Check ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[!] This script must be run as root${NC}"
   exit 1
fi

# --- Banner ---
clear
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  USVF - Unified Server Validation Framework v3.0          ║${NC}"
echo -e "${BLUE}║  Comprehensive Server Stress Testing & Benchmarking       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# --- Create Directory Structure ---
mkdir -p "$OUTPUT_DIR"/{logs,reports,raw_data}
mkdir -p "$MODULES_DIR"

# --- PID Tracking ---
PID_LIST=""

# --- Cleanup Function ---
cleanup() {
    echo -e "\n${YELLOW}[!] Signal Received. Cleaning up...${NC}"
    if [[ -n "$PID_LIST" ]]; then
        for pid in $PID_LIST; do
            kill -TERM $pid 2>/dev/null || true
        done
        sleep 2
        for pid in $PID_LIST; do
            kill -KILL $pid 2>/dev/null || true
        done
    fi
    pkill -f stress-ng 2>/dev/null || true
    pkill -f fio 2>/dev/null || true
    pkill -f iperf3 2>/dev/null || true
    pkill -f sysbench 2>/dev/null || true
    echo -e "${GREEN}[✓] Cleanup complete. Results saved in: $OUTPUT_DIR${NC}"
}
trap cleanup SIGINT SIGTERM EXIT

# --- Phase 0: Dependency Check & Installation ---
echo -e "${BLUE}[→] Phase 0: Checking dependencies...${NC}"
source "$MODULES_DIR/install-deps.sh"
install_dependencies

# --- Phase 1: Hardware Discovery ---
echo -e "${BLUE}[→] Phase 1: Hardware Discovery & Inventory...${NC}"
source "$MODULES_DIR/hardware-detect.sh"
detect_hardware
echo -e "${GREEN}[✓] Hardware inventory complete${NC}"
echo ""

# --- Phase 2: CPU Core Distribution ---
echo -e "${BLUE}[→] Phase 2: Calculating CPU Core Distribution...${NC}"
TOTAL_CORES=$(nproc)
echo "Total CPU Cores: $TOTAL_CORES"

# Distribute cores across different workloads
COMPUTE_CORES=$((TOTAL_CORES * 40 / 100))  # 40% for compute
STORAGE_CORES=$((TOTAL_CORES * 30 / 100))  # 30% for storage
NETWORK_CORES=$((TOTAL_CORES * 20 / 100))  # 20% for network
MEMORY_CORES=$((TOTAL_CORES * 10 / 100))   # 10% for memory

# Ensure at least 1 core per task
[[ $COMPUTE_CORES -lt 1 ]] && COMPUTE_CORES=1
[[ $STORAGE_CORES -lt 1 ]] && STORAGE_CORES=1
[[ $NETWORK_CORES -lt 1 ]] && NETWORK_CORES=1
[[ $MEMORY_CORES -lt 1 ]] && MEMORY_CORES=1

echo "  - Compute Stress: $COMPUTE_CORES cores"
echo "  - Storage Stress: $STORAGE_CORES cores"
echo "  - Network Stress: $NETWORK_CORES cores"
echo "  - Memory Stress: $MEMORY_CORES cores"
echo ""

# --- Phase 3: Launch Stress Tests ---
echo -e "${BLUE}[→] Phase 3: Launching Stress Tests...${NC}"

# 3.1 Launch Compute Stress
echo "[→] Starting CPU/Compute stress test..."
source "$MODULES_DIR/compute-stress.sh"
start_compute_stress "$COMPUTE_CORES" "$DURATION" "$OUTPUT_DIR" &
PID_COMPUTE=$!
PID_LIST="$PID_LIST $PID_COMPUTE"
echo -e "${GREEN}[✓] Compute stress launched (PID: $PID_COMPUTE)${NC}"

# 3.2 Launch Storage Stress
echo "[→] Starting Storage stress test..."
source "$MODULES_DIR/storage-stress.sh"
start_storage_stress "$STORAGE_CORES" "$DURATION" "$OUTPUT_DIR" &
PID_STORAGE=$!
PID_LIST="$PID_LIST $PID_STORAGE"
echo -e "${GREEN}[✓] Storage stress launched (PID: $PID_STORAGE)${NC}"

# 3.3 Launch Network Stress
echo "[→] Starting Network stress test..."
source "$MODULES_DIR/network-stress.sh"
start_network_stress "$NETWORK_CORES" "$DURATION" "$OUTPUT_DIR" &
PID_NETWORK=$!
PID_LIST="$PID_LIST $PID_NETWORK"
echo -e "${GREEN}[✓] Network stress launched (PID: $PID_NETWORK)${NC}"

# 3.4 Launch Memory Stress
echo "[→] Starting Memory stress test..."
source "$MODULES_DIR/memory-stress.sh"
start_memory_stress "$MEMORY_CORES" "$DURATION" "$OUTPUT_DIR" &
PID_MEMORY=$!
PID_LIST="$PID_LIST $PID_MEMORY"
echo -e "${GREEN}[✓] Memory stress launched (PID: $PID_MEMORY)${NC}"

sleep 2
echo ""

# --- Phase 4: Monitoring Loop ---
echo -e "${BLUE}[→] Phase 4: Real-time Monitoring...${NC}"
source "$MODULES_DIR/monitoring.sh"
start_monitoring "$DURATION" "$OUTPUT_DIR" "$PID_LIST"

# --- Phase 5: Wait for Completion ---
echo -e "${BLUE}[→] Waiting for all stress tests to complete...${NC}"
wait $PID_COMPUTE 2>/dev/null || true
wait $PID_STORAGE 2>/dev/null || true
wait $PID_NETWORK 2>/dev/null || true
wait $PID_MEMORY 2>/dev/null || true

# --- Phase 6: Generate Report ---
echo -e "${BLUE}[→] Phase 5: Generating Comprehensive Report...${NC}"
source "$MODULES_DIR/report-generator.sh"
generate_report "$OUTPUT_DIR"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Stress Testing Complete!                                  ║${NC}"
echo -e "${GREEN}║  Results: $OUTPUT_DIR${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "View the main report:"
echo "  cat $OUTPUT_DIR/reports/FINAL_REPORT.txt"
echo ""
