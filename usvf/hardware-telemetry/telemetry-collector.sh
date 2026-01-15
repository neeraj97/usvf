#!/bin/bash
# Hardware Telemetry Collector
# Main orchestration script for collecting comprehensive hardware telemetry

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
CONFIG_FILE="${SCRIPT_DIR}/config/telemetry.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

# Load utilities
source "${SCRIPT_DIR}/modules/utils.sh"

# Load telemetry modules
source "${SCRIPT_DIR}/modules/cpu_telemetry.sh"
source "${SCRIPT_DIR}/modules/memory_telemetry.sh"
source "${SCRIPT_DIR}/modules/storage_telemetry.sh"
source "${SCRIPT_DIR}/modules/network_telemetry.sh"
source "${SCRIPT_DIR}/modules/gpu_telemetry.sh"
source "${SCRIPT_DIR}/modules/system_telemetry.sh"

# Global variables for JSON output
TELEMETRY_JSON=""
declare -A TELEMETRY_MODULES

# Initialize telemetry collection
init_telemetry() {
    log_message "INFO" "Initializing hardware telemetry collection..."
    log_message "INFO" "Collection interval: ${COLLECTION_INTERVAL}s"
    log_message "INFO" "Output directory: $OUTPUT_DIR"
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$LOG_DIR"
    
    # Validate required tools
    local missing_tools=()
    
    for tool in lscpu free lsblk ip bc; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_message "WARNING" "Missing tools: ${missing_tools[*]}"
        log_message "WARNING" "Some telemetry data may be unavailable"
    fi
    
    # Check for optional tools
    local optional_tools="dmidecode smartctl sensors nvidia-smi ethtool ipmitool"
    for tool in $optional_tools; do
        if ! command_exists "$tool"; then
            log_message "INFO" "Optional tool not found: $tool"
        fi
    done
    
    log_message "INFO" "Initialization complete"
}

# Collect all telemetry
collect_all_telemetry() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local output_file="${OUTPUT_DIR}/telemetry_${timestamp}.txt"
    local json_file="${OUTPUT_DIR}/telemetry_${timestamp}.json"
    
    log_message "INFO" "Starting telemetry collection at $(date)"
    log_message "INFO" "Output file: $output_file"
    
    # Initialize output files
    init_output_file "$output_file"
    
    # Initialize JSON
    TELEMETRY_JSON="{\"timestamp\": \"$(date -Iseconds)\", \"hostname\": \"$(hostname)\", \"modules\": {"
    
    # Collect telemetry from each module
    if [[ "$ENABLE_CPU_TELEMETRY" == "true" ]]; then
        collect_cpu_telemetry
    fi
    
    if [[ "$ENABLE_MEMORY_TELEMETRY" == "true" ]]; then
        collect_memory_telemetry
    fi
    
    if [[ "$ENABLE_STORAGE_TELEMETRY" == "true" ]]; then
        collect_storage_telemetry
    fi
    
    if [[ "$ENABLE_NETWORK_TELEMETRY" == "true" ]]; then
        collect_network_telemetry
    fi
    
    if [[ "$ENABLE_GPU_TELEMETRY" == "true" ]]; then
        collect_gpu_telemetry
    fi
    
    # System telemetry (includes multiple sub-modules)
    collect_system_telemetry
    
    # Finalize JSON
    TELEMETRY_JSON="${TELEMETRY_JSON%,}}"  # Remove trailing comma
    TELEMETRY_JSON+="}}"
    
    # Save JSON output
    if [[ "$ENABLE_JSON_OUTPUT" == "true" ]]; then
        echo "$TELEMETRY_JSON" > "$json_file"
        log_message "INFO" "JSON telemetry saved to: $json_file"
    fi
    
    # Cleanup old files if rotation is enabled
    if [[ "$ENABLE_FILE_ROTATION" == "true" ]]; then
        cleanup_old_files
    fi
    
    log_message "INFO" "Telemetry collection completed at $(date)"
}

# Main execution
main() {
    log_message "INFO" "=== Hardware Telemetry Collector ==="
    log_message "INFO" "Version: 1.0.0"
    log_message "INFO" "Started at: $(date)"
    
    # Check if running as root for certain operations
    if [[ $EUID -ne 0 ]] && [[ "$REQUIRE_ROOT" == "true" ]]; then
        log_message "WARNING" "Not running as root. Some telemetry data may be unavailable."
        log_message "WARNING" "Consider running with sudo for full telemetry collection."
    fi
    
    # Parse command line arguments
    local mode="interval"
    local count=0
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --once)
                mode="once"
                shift
                ;;
            --count)
                count="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_message "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Initialize
    init_telemetry
    
    # Execute based on mode
    case "$mode" in
        once)
            collect_all_telemetry
            ;;
        interval)
            if [[ $count -gt 0 ]]; then
                log_message "INFO" "Running $count collection(s) at ${COLLECTION_INTERVAL}s intervals"
                for ((i=1; i<=count; i++)); do
                    log_message "INFO" "Collection $i of $count"
                    collect_all_telemetry
                    
                    if [[ $i -lt $count ]]; then
                        log_message "INFO" "Waiting ${COLLECTION_INTERVAL}s for next collection..."
                        sleep "$COLLECTION_INTERVAL"
                    fi
                done
            else
                log_message "INFO" "Running continuous collection at ${COLLECTION_INTERVAL}s intervals"
                log_message "INFO" "Press Ctrl+C to stop"
                
                while true; do
                    collect_all_telemetry
                    log_message "INFO" "Waiting ${COLLECTION_INTERVAL}s for next collection..."
                    sleep "$COLLECTION_INTERVAL"
                done
            fi
            ;;
    esac
    
    log_message "INFO" "Telemetry collector finished"
}

# Show usage information
show_usage() {
    cat << EOF
Hardware Telemetry Collector

Usage: $0 [OPTIONS]

OPTIONS:
    --once          Run telemetry collection once and exit
    --count N       Run N collections at the configured interval and exit
    --help, -h      Show this help message

EXAMPLES:
    # Run once
    $0 --once
    
    # Run 10 collections
    $0 --count 10
    
    # Run continuously (default)
    $0

CONFIGURATION:
    Edit config/telemetry.conf to customize collection settings

OUTPUT:
    Telemetry files are saved to: $OUTPUT_DIR
    Log files are saved to: $LOG_DIR

EOF
}

# Trap signals for cleanup
trap 'log_message "INFO" "Received interrupt signal. Exiting..."; exit 0' SIGINT SIGTERM

# Run main
main "$@"
