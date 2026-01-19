#!/bin/bash
# SAVE AS: healthcheck.sh

LOG_FILE="/mnt/flash/health_report_detailed.txt"

# --- HELPER FUNCTIONS ---

# Function to write to log and print to screen
log() {
    echo "$1" | tee -a $LOG_FILE
}

# Function to run a command, log the output, and return it for checking
run_cmd() {
    CMD="$1"
    SECTION_TITLE="$2"
    
    log ""
    log "========================================"
    log " $SECTION_TITLE"
    log " Command: $CMD"
    log "========================================"
    
    # Run the command using FastCli
    OUTPUT=$(FastCli -p 15 -c "$CMD")
    
    # Save the actual output to the file
    echo "$OUTPUT" >> $LOG_FILE
    
    # Return output for logic checks
    echo "$OUTPUT"
}

# --- START SCRIPT ---

# Initialize Log File
echo "--- ARISTA DETAILED HEALTH REPORT ---" > $LOG_FILE
echo "Date: $(date)" >> $LOG_FILE
echo "Hostname: $(hostname)" >> $LOG_FILE

# 1. SWITCH DETAILS (Model, Serial, OS)
OUT_VER=$(run_cmd "show version" "SWITCH SYSTEM DETAILS")
# No Pass/Fail logic needed here, just information

# 2. LICENSE STATUS
OUT_LIC=$(run_cmd "show license" "LICENSE INFORMATION")
# Check if output contains 'No license' or specific errors (optional logic)
# We just log it for review as requested.

# 3. COOLING & FANS
OUT_COOL=$(run_cmd "show system environment cooling" "COOLING SYSTEM CHECK")
if echo "$OUT_COOL" | grep -q "System cooling status is: Ok"; then
    log " -> STATUS: [PASS] Cooling is functioning correctly."
else
    log " -> STATUS: [FAIL] Check Fan Modules!"
fi

# 4. TEMPERATURE SENSORS
OUT_TEMP=$(run_cmd "show system environment temperature" "TEMPERATURE SENSORS")
if echo "$OUT_TEMP" | grep -q "Overheat"; then
    log " -> STATUS: [FAIL] Overheating detected!"
else
    log " -> STATUS: [PASS] Temperatures within normal limits."
fi

# 5. POWER SUPPLIES
OUT_PWR=$(run_cmd "show environment power" "POWER SUPPLY CHECK")
# Simple check: pass if we see at least one 'Ok'
if echo "$OUT_PWR" | grep -E "Ok"; then
    log " -> STATUS: [PASS] Power detected."
else
    log " -> STATUS: [FAIL] No Power Supplies listed as OK."
fi

# 6. HARDWARE MODULES (ASIC Health)
OUT_MOD=$(run_cmd "show module" "MODULE & ASIC STATUS")
if echo "$OUT_MOD" | grep -qE "Active|Ok"; then
    log " -> STATUS: [PASS] Supervisor and Linecards are Active."
else
    log " -> STATUS: [FAIL] Modules are not reporting 'Active'."
fi

# 7. INVENTORY (Physical Serials)
# Good for verifying refurbished parts
run_cmd "show inventory" "PHYSICAL INVENTORY"

run_cmd "show interfaces status" "INTERFACES STATUS" 

# 8. hardware capacity (Physical Serials)
run_cmd "show hardware capacity" "HARDWARE CAPACITY"

# 9. FLASH STORAGE
log ""
log "========================================"
log " FLASH STORAGE CHECK"
log "========================================"
# Check disk space
df -h /mnt/flash >> $LOG_FILE

# Write Test
if touch /mnt/flash/test_write && rm /mnt/flash/test_write; then
    log " -> STATUS: [PASS] Flash is Writable."
else
    log " -> STATUS: [FAIL] Flash is Read-Only or Corrupt."
fi

log ""
log "========================================"
log "TEST COMPLETE"
log "Report saved to: $LOG_FILE"
log "========================================"