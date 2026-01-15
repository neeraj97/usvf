#!/bin/bash
# Compute/CPU Stress Testing Module

start_compute_stress() {
    local CORES=$1
    local DURATION=$2
    local OUTPUT=$3
    
    local LOG_FILE="$OUTPUT/logs/compute_stress.log"
    local RESULTS_FILE="$OUTPUT/raw_data/compute_results.yaml"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting CPU/Compute stress test" | tee "$LOG_FILE"
    echo "Assigned Cores: $CORES" | tee -a "$LOG_FILE"
    echo "Duration: $DURATION seconds" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # Calculate core range
    local CORE_START=0
    local CORE_END=$((CORES - 1))
    
    # Run multiple stress methods for comprehensive testing
    echo "[→] Running matrix multiplication stress (high heat generation)..." | tee -a "$LOG_FILE"
    stress-ng \
        --cpu "$CORES" \
        --cpu-method matrixprod \
        --timeout "$DURATION" \
        --metrics-brief \
        --tz \
        --yaml "$RESULTS_FILE" \
        --log-file "$LOG_FILE" \
        --verify &
    
    local PID_MATRIX=$!
    echo "Matrix stress PID: $PID_MATRIX" | tee -a "$LOG_FILE"
    
    # Wait for completion
    wait $PID_MATRIX
    
    # Run additional CPU-intensive operations
    echo "[→] Running FFT stress test..." | tee -a "$LOG_FILE"
    stress-ng \
        --cpu "$CORES" \
        --cpu-method fft \
        --timeout $((DURATION / 3)) \
        --metrics-brief \
        --yaml "${RESULTS_FILE}.fft" \
        --log-file "$LOG_FILE" &
    
    local PID_FFT=$!
    wait $PID_FFT
    
    echo "[→] Running floating point operations..." | tee -a "$LOG_FILE"
    stress-ng \
        --cpu "$CORES" \
        --cpu-method ackermann \
        --timeout $((DURATION / 3)) \
        --metrics-brief \
        --yaml "${RESULTS_FILE}.ackermann" \
        --log-file "$LOG_FILE" &
    
    local PID_ACK=$!
    wait $PID_ACK
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Compute stress test complete" | tee -a "$LOG_FILE"
}
