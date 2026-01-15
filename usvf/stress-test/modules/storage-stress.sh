#!/bin/bash
# Storage Stress Testing Module

start_storage_stress() {
    local CORES=$1
    local DURATION=$2
    local OUTPUT=$3
    
    local LOG_FILE="$OUTPUT/logs/storage_stress.log"
    local STORAGE_DEVICES_FILE="$OUTPUT/raw_data/storage_devices.txt"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Storage stress test" | tee "$LOG_FILE"
    echo "Assigned Cores: $CORES" | tee -a "$LOG_FILE"
    echo "Duration: $DURATION seconds" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # Check if storage devices were detected
    if [[ ! -f "$STORAGE_DEVICES_FILE" ]]; then
        echo "[!] No storage devices detected. Creating test directory in /tmp" | tee -a "$LOG_FILE"
        TEST_DIR="/tmp/usvf_storage_test"
        mkdir -p "$TEST_DIR"
        run_fio_test "$TEST_DIR" "$CORES" "$DURATION" "$OUTPUT" "TMP"
        return
    fi
    
    # Test each detected storage device
    local DEVICE_COUNT=0
    while IFS='|' read -r device model size type serial; do
        DEVICE_COUNT=$((DEVICE_COUNT + 1))
        
        echo "" | tee -a "$LOG_FILE"
        echo "======================================" | tee -a "$LOG_FILE"
        echo "Testing Device $DEVICE_COUNT: $device" | tee -a "$LOG_FILE"
        echo "  Model: $model" | tee -a "$LOG_FILE"
        echo "  Size: $size" | tee -a "$LOG_FILE"
        echo "  Type: $type" | tee -a "$LOG_FILE"
        echo "  Serial: $serial" | tee -a "$LOG_FILE"
        echo "======================================" | tee -a "$LOG_FILE"
        
        # Create a unique test directory for this device
        # We'll test in /tmp for safety (non-destructive)
        TEST_DIR="/tmp/usvf_storage_test_${DEVICE_COUNT}"
        mkdir -p "$TEST_DIR"
        
        # Run FIO tests on this directory
        run_fio_test "$TEST_DIR" "$CORES" "$DURATION" "$OUTPUT" "$type" "$device" "$model"
        
        # Cleanup test directory
        rm -rf "$TEST_DIR"
        
    done < "$STORAGE_DEVICES_FILE"
    
    echo "" | tee -a "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Storage stress test complete" | tee -a "$LOG_FILE"
}

run_fio_test() {
    local TEST_DIR=$1
    local CORES=$2
    local DURATION=$3
    local OUTPUT=$4
    local DEVICE_TYPE=$5
    local DEVICE_PATH=${6:-"unknown"}
    local DEVICE_MODEL=${7:-"unknown"}
    
    local SAFE_DEVICE_NAME=$(echo "$DEVICE_PATH" | tr '/' '_')
    local FIO_JOB="$OUTPUT/raw_data/fio_job_${SAFE_DEVICE_NAME}.fio"
    local FIO_RESULTS="$OUTPUT/raw_data/fio_results_${SAFE_DEVICE_NAME}.json"
    local LOG_FILE="$OUTPUT/logs/storage_stress.log"
    
    # Determine optimal settings based on device type
    local IODEPTH=32
    local NUMJOBS=$CORES
    local FILESIZE="4G"
    
    if [[ "$DEVICE_TYPE" == "NVMe" ]]; then
        IODEPTH=128
        echo "[→] Optimized for NVMe (high queue depth)" | tee -a "$LOG_FILE"
    elif [[ "$DEVICE_TYPE" == "SSD" ]]; then
        IODEPTH=64
        echo "[→] Optimized for SSD" | tee -a "$LOG_FILE"
    elif [[ "$DEVICE_TYPE" == "HDD" ]]; then
        IODEPTH=16
        NUMJOBS=$((CORES / 2))
        [[ $NUMJOBS -lt 1 ]] && NUMJOBS=1
        echo "[→] Optimized for HDD (lower queue depth)" | tee -a "$LOG_FILE"
    fi
    
    # Create FIO job file for comprehensive testing
    cat > "$FIO_JOB" <<EOF
[global]
ioengine=libaio
direct=1
gtod_reduce=1
group_reporting=1
time_based=1
runtime=$DURATION
directory=$TEST_DIR
filename=fio_test_file

# Sequential Read Test
[seq-read]
rw=read
bs=1M
iodepth=$IODEPTH
numjobs=$NUMJOBS
stonewall

# Sequential Write Test
[seq-write]
rw=write
bs=1M
iodepth=$IODEPTH
numjobs=$NUMJOBS
stonewall

# Random Read Test (4K blocks)
[rand-read-4k]
rw=randread
bs=4k
iodepth=$IODEPTH
numjobs=$NUMJOBS
stonewall

# Random Write Test (4K blocks)
[rand-write-4k]
rw=randwrite
bs=4k
iodepth=$IODEPTH
numjobs=$NUMJOBS
stonewall

# Mixed Random Read/Write (70/30)
[rand-rw-mix]
rw=randrw
rwmixread=70
bs=4k
iodepth=$IODEPTH
numjobs=$NUMJOBS
stonewall
EOF
    
    echo "[→] Running FIO benchmark suite..." | tee -a "$LOG_FILE"
    echo "    Job File: $FIO_JOB" | tee -a "$LOG_FILE"
    echo "    Results: $FIO_RESULTS" | tee -a "$LOG_FILE"
    
    # Run FIO
    fio --output-format=json+ --output="$FIO_RESULTS" "$FIO_JOB" 2>&1 | tee -a "$LOG_FILE"
    
    # Check if test completed successfully
    if [[ -f "$FIO_RESULTS" ]]; then
        echo "[✓] FIO test completed for $DEVICE_TYPE" | tee -a "$LOG_FILE"
        
        # Extract key metrics using jq
        if command -v jq &> /dev/null; then
            echo "" | tee -a "$LOG_FILE"
            echo "Quick Results Summary:" | tee -a "$LOG_FILE"
            
            # Try to extract metrics (FIO JSON format can vary)
            SEQ_READ=$(jq -r '.jobs[] | select(.jobname=="seq-read") | .read.bw // 0' "$FIO_RESULTS" 2>/dev/null || echo "N/A")
            SEQ_WRITE=$(jq -r '.jobs[] | select(.jobname=="seq-write") | .write.bw // 0' "$FIO_RESULTS" 2>/dev/null || echo "N/A")
            RAND_READ=$(jq -r '.jobs[] | select(.jobname=="rand-read-4k") | .read.iops // 0' "$FIO_RESULTS" 2>/dev/null || echo "N/A")
            RAND_WRITE=$(jq -r '.jobs[] | select(.jobname=="rand-write-4k") | .write.iops // 0' "$FIO_RESULTS" 2>/dev/null || echo "N/A")
            
            echo "  Sequential Read: $SEQ_READ KB/s" | tee -a "$LOG_FILE"
            echo "  Sequential Write: $SEQ_WRITE KB/s" | tee -a "$LOG_FILE"
            echo "  Random Read IOPS: $RAND_READ" | tee -a "$LOG_FILE"
            echo "  Random Write IOPS: $RAND_WRITE" | tee -a "$LOG_FILE"
        fi
    else
        echo "[!] FIO test may have failed. Check logs." | tee -a "$LOG_FILE"
    fi
    
    echo "" | tee -a "$LOG_FILE"
}
