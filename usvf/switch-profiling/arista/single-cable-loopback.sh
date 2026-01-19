#!/bin/bash
# SAVE AS: final_prbs_report.sh

LOG_FILE="/mnt/flash/prbs_hardware_report.txt"
ANCHOR_PORT=""

# --- HELPER FUNCTIONS ---
log() { echo "$1" | tee -a $LOG_FILE; }
run_fastcli() { FastCli -p 15 -c "$1"; }

# --- 0. SYSTEM INFO HEADER ---
generate_header() {
    echo "==================================================" > $LOG_FILE
    echo "       ARISTA SWITCH HARDWARE VALIDATION          " >> $LOG_FILE
    echo "==================================================" >> $LOG_FILE
    echo "Test Date    : $(date)" >> $LOG_FILE
    
    # Capture System Details
    echo "" >> $LOG_FILE
    echo "--- SYSTEM INFORMATION ---" >> $LOG_FILE
    
    # Run 'show version' and extract key lines
    SYS_INFO=$(run_fastcli "show version")
    MODEL=$(echo "$SYS_INFO" | grep "Model" | awk '{print $3}')
    SERIAL=$(echo "$SYS_INFO" | grep "Serial number" | awk '{print $3}')
    EOS_VER=$(echo "$SYS_INFO" | grep "Software image version" | awk '{print $4}')
    MAC=$(echo "$SYS_INFO" | grep "System MAC address" | awk '{print $4}')

    echo "Model        : $MODEL" >> $LOG_FILE
    echo "Serial No    : $SERIAL" >> $LOG_FILE
    echo "EOS Version  : $EOS_VER" >> $LOG_FILE
    echo "System MAC   : $MAC" >> $LOG_FILE

    # Capture License Status
    echo "" >> $LOG_FILE
    echo "--- LICENSE STATUS ---" >> $LOG_FILE
    run_fastcli "show license" >> $LOG_FILE
    
    echo "" >> $LOG_FILE
    echo "--------------------------------------------------" >> $LOG_FILE
    echo "Starting PRBS Bandwidth & Signal Integrity Test..." >> $LOG_FILE
    echo "--------------------------------------------------" >> $LOG_FILE
    
    # Print to screen for user confirmation
    echo "System Info Captured:"
    echo "Model: $MODEL | Serial: $SERIAL"
}

# --- 1. ANCHOR DETECTION ---
get_anchor() {
    echo ""
    echo "STEP 1: SELECT ANCHOR PORT (STATIONARY END)"
    echo "Plug the cable into the Anchor Port now."
    
    while [ -z "$ANCHOR_PORT" ]; do
        RAW_LIST=$(run_fastcli "show interfaces status connected")
        CANDIDATE=$(echo "$RAW_LIST" | grep "^Et" | awk '{print $1}' | head -n 1)
        
        if [[ $CANDIDATE == Et* ]]; then
            SPEED_INFO=$(echo "$RAW_LIST" | grep "$CANDIDATE" | awk '{print $5, $6}')
            echo ""
            echo ">>> DETECTED: $CANDIDATE ($SPEED_INFO) <<<"
            read -p "Use as Anchor? (y/n): " CONFIRM
            if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
                ANCHOR_PORT=$CANDIDATE
                log "[*] ANCHOR LOCKED: $ANCHOR_PORT"
                
                # Bring Anchor UP (Clean Config)
                run_fastcli "conf t
                default interface $ANCHOR_PORT
                interface $ANCHOR_PORT
                no switchport
                no shutdown
                end" > /dev/null
            fi
        fi
        sleep 1
    done
}

# --- 2. TEST EXECUTION ---
run_prbs_test() {
    TARGET=$1
    log ""
    log "========================================"
    log " TESTING PORT: $TARGET"
    log "========================================"

    # A. IDENTIFY BANDWIDTH & TRANSCEIVER
    log "[*] Verifying Link Parameters..."
    
    STATUS_LINE=$(run_fastcli "show interfaces $TARGET status" | grep "$TARGET")
    SPEED=$(echo "$STATUS_LINE" | awk '{print $5}')
    TYPE=$(echo "$STATUS_LINE" | awk '{print $6}')
    
    # Get Transceiver Serial
    XCVR=$(run_fastcli "show interfaces $TARGET transceiver hardware" | grep "Serial Number")
    XCVR_SN=$(echo $XCVR | awk '{print $3}')
    
    log "    -> Speed (Bandwidth): $SPEED"
    log "    -> Media Type       : $TYPE"
    log "    -> Transceiver SN   : $XCVR_SN"

    # B. START PRBS (STRESS TEST)
    log "[*] Starting PRBS31 Generation (Line Rate)..."
    
    # Use split TX/RX command syntax
    run_fastcli "configure terminal
    interface $ANCHOR_PORT, $TARGET
       phy diag transmitter pattern prbs31
       phy diag receiver pattern prbs31
       no shutdown
    end" > /dev/null
    
    log "    -> Generating Signal... (Waiting 10s for Lock)"
    sleep 10
    
    # C. CHECK RESULTS
    RES=$(run_fastcli "show interfaces $TARGET phy diag receiver")
    
    # Fallback check
    if [ -z "$RES" ]; then
         RES=$(run_fastcli "show interfaces $TARGET phy diagnostic-mode prbs")
    fi

    # Logic: Check for Lock AND Errors
    if echo "$RES" | grep -qE "Locked: Yes|Sync: Yes|Lock: true"; then
        LOCK_STATUS="LOCKED"
    else
        LOCK_STATUS="FAILED"
    fi
    
    ERR_COUNT=$(echo "$RES" | grep -i "Error Count" | awk '{print $NF}')
    
    if [[ "$LOCK_STATUS" == "LOCKED" ]]; then
        if [[ "$ERR_COUNT" == "0" ]]; then
            log "    -> [PASS] BANDWIDTH CONFIRMED. SIGNAL PERFECT."
            log "       (Locked: Yes | Errors: 0)"
        else
            log "    -> [FAIL] SIGNAL DIRTY. (Errors Detected: $ERR_COUNT)"
        fi
    else
        log "    -> [FAIL] NO LOCK. LINK UNSTABLE."
    fi

    # D. CLEANUP
    log "[*] Resetting Port..."
    run_fastcli "configure terminal
    default interface $TARGET
    interface $ANCHOR_PORT
       no phy diag transmitter
       no phy diag receiver
    end" > /dev/null
}

# --- MAIN LOOP ---

# 1. Generate Header with System Info
generate_header

# 2. Get Anchor
get_anchor

# 3. Test Loop
log "---------------------------------------------------"
log " SYSTEM READY. PLUG CABLE INTO NEXT PORT."
log "---------------------------------------------------"

while true; do
    RAW_LIST=$(run_fastcli "show interfaces status connected")
    # Find new port (Not Anchor)
    NEW_PORT=$(echo "$RAW_LIST" | grep "^Et" | awk -v anchor="$ANCHOR_PORT" '$1 != anchor {print $1}' | head -n 1)
    
    if [[ ! -z "$NEW_PORT" && $NEW_PORT == Et* ]]; then
         run_prbs_test $NEW_PORT
         
         log ">>> TEST COMPLETE. UNPLUG $NEW_PORT <<<" 
         
         while true; do
             STATUS=$(run_fastcli "show interfaces $NEW_PORT status")
             if echo "$STATUS" | grep -q "notconnect"; then break; fi
             sleep 1
         done
    fi
    sleep 1
done