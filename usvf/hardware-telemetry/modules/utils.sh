#!/bin/bash
# Hardware Telemetry Utility Functions
# Provides common functions for logging, formatting, and utility operations

# === LOGGING FUNCTIONS ===

# Initialize logging
init_logging() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local hostname=$(hostname -s)
    local log_pattern="${LOG_FILE_PATTERN:-{hostname}_telemetry_{timestamp}.log}"
    
    # Replace patterns
    log_pattern="${log_pattern//\{timestamp\}/$timestamp}"
    log_pattern="${log_pattern//\{date\}/$(date +%Y%m%d)}"
    log_pattern="${log_pattern//\{time\}/$(date +%H%M%S)}"
    log_pattern="${log_pattern//\{hostname\}/$hostname}"
    
    LOG_FILE="${TELEMETRY_OUTPUT_DIR}/${log_pattern}"
    JSON_FILE="${TELEMETRY_OUTPUT_DIR}/${hostname}_telemetry_${timestamp}.json"
    CSV_FILE="${TELEMETRY_OUTPUT_DIR}/${hostname}_telemetry_${timestamp}.csv"
    
    # Create output directory if it doesn't exist
    mkdir -p "${TELEMETRY_OUTPUT_DIR}"
    
    # Initialize log files
    echo "# Hardware Telemetry Log - $(date)" > "$LOG_FILE"
    echo "# Hostname: $hostname" >> "$LOG_FILE"
    echo "# Start Time: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    # Initialize JSON
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "{" > "$JSON_FILE"
        echo "  \"collection_info\": {" >> "$JSON_FILE"
        echo "    \"hostname\": \"$hostname\"," >> "$JSON_FILE"
        echo "    \"start_time\": \"$(date -Iseconds)\"," >> "$JSON_FILE"
        echo "    \"interval_seconds\": $TELEMETRY_INTERVAL" >> "$JSON_FILE"
        echo "  }," >> "$JSON_FILE"
        echo "  \"snapshots\": [" >> "$JSON_FILE"
    fi
    
    export LOG_FILE JSON_FILE CSV_FILE
}

# Log message to file
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    if [[ "$VERBOSE_MODE" == "true" ]] || [[ "$level" == "ERROR" ]] || [[ "$level" == "WARNING" ]]; then
        echo "[$timestamp] [$level] $message"
    fi
}

# Log telemetry data
log_telemetry() {
    local module="$1"
    local data="$2"
    
    echo "=== $module Telemetry ===" >> "$LOG_FILE"
    echo "$data" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

# === JSON FUNCTIONS ===

# Start JSON snapshot
json_start_snapshot() {
    local snapshot_time=$(date -Iseconds)
    
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        return
    fi
    
    # Add comma if not first snapshot
    if [[ -f "${JSON_FILE}.tmp" ]]; then
        echo "," >> "$JSON_FILE"
    fi
    
    cat >> "$JSON_FILE" << EOF
    {
      "timestamp": "$snapshot_time",
EOF
}

# Add JSON module data
json_add_module() {
    local module="$1"
    local data="$2"
    
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        return
    fi
    
    echo "      \"$module\": $data," >> "$JSON_FILE"
}

# End JSON snapshot
json_end_snapshot() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        return
    fi
    
    # Remove trailing comma and close snapshot
    sed -i '$ s/,$//' "$JSON_FILE" 2>/dev/null || sed -i '' '$ s/,$//' "$JSON_FILE"
    echo "    }" >> "$JSON_FILE"
    
    # Mark that we have snapshots
    touch "${JSON_FILE}.tmp"
}

# Finalize JSON file
json_finalize() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        return
    fi
    
    echo "  ]," >> "$JSON_FILE"
    echo "  \"collection_info_end\": {" >> "$JSON_FILE"
    echo "    \"end_time\": \"$(date -Iseconds)\"" >> "$JSON_FILE"
    echo "  }" >> "$JSON_FILE"
    echo "}" >> "$JSON_FILE"
    
    # Clean up temp file
    rm -f "${JSON_FILE}.tmp"
}

# === CSV FUNCTIONS ===

# Initialize CSV headers
csv_init_headers() {
    if [[ "$CSV_OUTPUT" != "true" ]]; then
        return
    fi
    
    local headers="Timestamp"
    headers="$headers,Hostname"
    
    # Add module-specific headers (will be populated by modules)
    export CSV_HEADERS="$headers"
}

# Add CSV row
csv_add_row() {
    local data="$1"
    
    if [[ "$CSV_OUTPUT" != "true" ]]; then
        return
    fi
    
    echo "$data" >> "$CSV_FILE"
}

# === FORMATTING FUNCTIONS ===

# Format bytes to human readable
format_bytes() {
    local bytes=$1
    local units=("B" "KB" "MB" "GB" "TB" "PB")
    local unit_index=0
    local size=$bytes
    
    while (( $(echo "$size >= 1024" | bc -l) )) && (( unit_index < 5 )); do
        size=$(echo "scale=2; $size / 1024" | bc)
        ((unit_index++))
    done
    
    echo "${size} ${units[$unit_index]}"
}

# Format percentage
format_percentage() {
    local value=$1
    local total=$2
    
    if [[ $total -eq 0 ]]; then
        echo "0.00%"
        return
    fi
    
    local percentage=$(echo "scale=2; ($value / $total) * 100" | bc)
    echo "${percentage}%"
}

# Format temperature
format_temperature() {
    local temp_c=$1
    echo "${temp_c}°C"
}

# Convert temperature from millidegrees to degrees
millidegree_to_celsius() {
    local temp_md=$1
    echo "scale=1; $temp_md / 1000" | bc
}

# === DEVICE DETECTION FUNCTIONS ===

# Detect all storage devices
detect_storage_devices() {
    local devices=()
    
    # Detect NVMe devices
    if command -v nvme &>/dev/null; then
        while IFS= read -r dev; do
            [[ -z "$dev" ]] && continue
            devices+=("$dev|nvme")
        done < <(nvme list 2>/dev/null | grep "^/dev/nvme" | awk '{print $1}')
    fi
    
    # Detect block devices (SSD/HDD)
    while IFS= read -r line; do
        local dev_name=$(echo "$line" | awk '{print $1}')
        local is_rota=$(echo "$line" | awk '{print $2}')
        
        # Skip NVMe devices (already processed)
        [[ "$dev_name" == nvme* ]] && continue
        
        local dev_path="/dev/$dev_name"
        if [[ "$is_rota" == "0" ]]; then
            devices+=("$dev_path|ssd")
        else
            devices+=("$dev_path|hdd")
        fi
    done < <(lsblk -d -n -o NAME,ROTA,TYPE 2>/dev/null | grep "disk")
    
    printf '%s\n' "${devices[@]}"
}

# Detect network interfaces
detect_network_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v "^lo$"
}

# Detect GPUs
detect_gpus() {
    local gpus=()
    
    # NVIDIA GPUs
    if command -v nvidia-smi &>/dev/null; then
        while IFS= read -r gpu; do
            [[ -z "$gpu" ]] && continue
            gpus+=("nvidia|$gpu")
        done < <(nvidia-smi -L 2>/dev/null | awk -F': ' '{print $1}')
    fi
    
    # AMD GPUs
    if command -v rocm-smi &>/dev/null; then
        while IFS= read -r gpu; do
            [[ -z "$gpu" ]] && continue
            gpus+=("amd|$gpu")
        done < <(rocm-smi --showid 2>/dev/null | grep "^GPU" | awk '{print $1}')
    fi
    
    # Intel GPUs (via sysfs)
    if [[ -d /sys/class/drm ]]; then
        while IFS= read -r card; do
            [[ -z "$card" ]] && continue
            local vendor=$(cat "/sys/class/drm/$card/device/vendor" 2>/dev/null)
            if [[ "$vendor" == "0x8086" ]]; then
                gpus+=("intel|$card")
            fi
        done < <(ls /sys/class/drm/ 2>/dev/null | grep "^card[0-9]$")
    fi
    
    printf '%s\n' "${gpus[@]}"
}

# Detect RAID controllers
detect_raid_controllers() {
    local controllers=()
    
    # MegaRAID
    if command -v megacli &>/dev/null || command -v storcli &>/dev/null; then
        controllers+=("megaraid")
    fi
    
    # Hardware RAID via lspci
    while IFS= read -r raid; do
        [[ -z "$raid" ]] && continue
        controllers+=("$raid")
    done < <(lspci 2>/dev/null | grep -i "raid" | cut -d: -f1)
    
    # Software RAID (mdadm)
    if command -v mdadm &>/dev/null; then
        if [[ -f /proc/mdstat ]] && grep -q "^md" /proc/mdstat 2>/dev/null; then
            controllers+=("mdadm")
        fi
    fi
    
    printf '%s\n' "${controllers[@]}"
}

# Check if BMC/IPMI is available
check_bmc_available() {
    if command -v ipmitool &>/dev/null; then
        if ipmitool mc info &>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# === SYSTEM INFO FUNCTIONS ===

# Get system uptime in seconds
get_uptime_seconds() {
    cat /proc/uptime | awk '{print $1}'
}

# Get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Get ISO timestamp
get_timestamp_iso() {
    date -Iseconds
}

# === ERROR HANDLING ===

# Check if command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]] && [[ "$REQUIRE_ROOT" == "true" ]]; then
        log_message "ERROR" "This script requires root privileges. Please run with sudo."
        return 1
    fi
    return 0
}

# Safe command execution
safe_execute() {
    local cmd="$1"
    local error_msg="${2:-Command failed}"
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        log_message "DEBUG" "Executing: $cmd"
    fi
    
    local output
    if output=$(eval "$cmd" 2>&1); then
        echo "$output"
        return 0
    else
        log_message "ERROR" "$error_msg: $output"
        if [[ "$CONTINUE_ON_ERROR" != "true" ]]; then
            return 1
        fi
        return 0
    fi
}

# === CLEANUP FUNCTIONS ===

# Cleanup old log files
cleanup_old_logs() {
    if [[ "$AUTO_CLEANUP" != "true" ]]; then
        return
    fi
    
    log_message "INFO" "Cleaning up logs older than $LOG_RETENTION_DAYS days"
    
    find "$TELEMETRY_OUTPUT_DIR" -type f -name "*.log" -mtime "+$LOG_RETENTION_DAYS" -delete 2>/dev/null
    find "$TELEMETRY_OUTPUT_DIR" -type f -name "*.json" -mtime "+$LOG_RETENTION_DAYS" -delete 2>/dev/null
    find "$TELEMETRY_OUTPUT_DIR" -type f -name "*.csv" -mtime "+$LOG_RETENTION_DAYS" -delete 2>/dev/null
}

# Export functions for use in other modules
export -f log_message log_telemetry
export -f json_start_snapshot json_add_module json_end_snapshot json_finalize
export -f csv_init_headers csv_add_row
export -f format_bytes format_percentage format_temperature millidegree_to_celsius
export -f detect_storage_devices detect_network_interfaces detect_gpus detect_raid_controllers check_bmc_available
export -f get_uptime_seconds get_timestamp get_timestamp_iso
export -f command_exists check_root safe_execute cleanup_old_logs
