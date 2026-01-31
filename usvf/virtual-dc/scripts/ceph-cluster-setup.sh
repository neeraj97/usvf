#!/bin/bash
#
# Ceph Cluster One-Click Setup Script
# Architecture:
#   Control Plane (MON/MGR): hypervisor-1, hypervisor-2, hypervisor-3
#   Data Plane (OSD): hypervisor-4, hypervisor-5
#
# Run this script from: hetzner machine
# Usage: ./ceph-cluster-setup.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BOOTSTRAP_HOST="hypervisor-1"
BOOTSTRAP_IP="192.168.10.11"
CONTROL_HOSTS=("hypervisor-1" "hypervisor-2" "hypervisor-3")
CONTROL_IPS=("192.168.10.11" "192.168.10.12" "192.168.10.13")
OSD_HOSTS=("hypervisor-4" "hypervisor-5")
OSD_IPS=("192.168.10.14" "192.168.10.15")
ALL_HOSTS=("hypervisor-1" "hypervisor-2" "hypervisor-3" "hypervisor-4" "hypervisor-5")

# RBD and RGW Configuration
RBD_POOL="rbd_data"
RBD_USER="rbduser"
RGW_USER="s3user"
RGW_PORT=8000

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

run_on_host() {
    local host=$1
    shift
    ssh "$host" "$@"
}

run_ceph_cmd() {
    # Run ceph command via cephadm shell on bootstrap host
    ssh "$BOOTSTRAP_HOST" "sudo cephadm shell -- $*"
}

wait_for_health() {
    local max_attempts=${1:-60}
    local attempt=0
    log_info "Waiting for Ceph cluster to become healthy..."
    while [ $attempt -lt $max_attempts ]; do
        if run_ceph_cmd ceph health 2>/dev/null | grep -q "HEALTH_OK\|HEALTH_WARN"; then
            log_info "Ceph cluster is healthy"
            return 0
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 5
    done
    log_warn "Cluster not fully healthy after $max_attempts attempts, continuing anyway..."
    return 0
}

# ============================================================================
# PHASE 0: Fix SSH known_hosts and wait for hosts to be ready
# ============================================================================
phase0_fix_ssh_keys() {
    log_info "=== PHASE 0: Fixing SSH known_hosts and waiting for hosts ==="

    # Remove old host keys for all IPs and hostnames
    log_info "Removing old SSH host keys..."
    for entry in "${ALL_HOSTS[@]}" "${CONTROL_IPS[@]}" "${OSD_IPS[@]}"; do
        ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$entry" 2>/dev/null || true
    done

    # Wait for all hosts to be reachable (max 5 minutes)
    log_info "Waiting for all hosts to be reachable..."
    local max_wait=300
    local wait_interval=10
    local elapsed=0

    while [ $elapsed -lt $max_wait ]; do
        local all_ready=true
        for ip in "${CONTROL_IPS[@]}" "${OSD_IPS[@]}"; do
            if ! nc -z -w 2 "$ip" 22 2>/dev/null; then
                all_ready=false
                break
            fi
        done

        if $all_ready; then
            log_info "All hosts are reachable!"
            break
        fi

        echo -n "."
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done

    if [ $elapsed -ge $max_wait ]; then
        log_error "Timeout waiting for hosts to be ready. Please ensure all VMs are running."
        exit 1
    fi

    # Wait for VMs to stabilize (unattended-upgrades may be running)
    log_info "Waiting for VMs to stabilize..."
    sleep 30

    # Scan and add new host keys
    log_info "Scanning and adding new SSH host keys..."
    for ip in "${CONTROL_IPS[@]}" "${OSD_IPS[@]}"; do
        ssh-keyscan -H "$ip" >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
    done

    # Verify SSH connectivity to all hosts
    log_info "Verifying SSH connectivity..."
    for host in "${ALL_HOSTS[@]}"; do
        if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$host" "hostname" > /dev/null 2>&1; then
            log_error "Cannot SSH to $host. Please check connectivity."
            exit 1
        fi
        log_info "  $host: OK"
    done

    log_info "Phase 0 complete: All hosts ready"
}

# ============================================================================
# PHASE 1: Prerequisites on all hosts
# ============================================================================
wait_for_apt() {
    local host=$1
    local max_wait=120
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if ssh "$host" "! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1" 2>/dev/null; then
            return 0
        fi
        echo -n "."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}

phase1_prerequisites() {
    log_info "=== PHASE 1: Installing prerequisites on all hosts ==="

    # First, wait for apt to be free on all hosts (unattended-upgrades may be running)
    log_info "Waiting for apt locks to be released on all hosts..."
    for host in "${ALL_HOSTS[@]}"; do
        log_info "  Waiting for apt on $host..."
        if ! wait_for_apt "$host"; then
            log_warn "Apt lock timeout on $host, trying to kill blocking processes..."
            ssh "$host" "sudo killall -9 apt-get apt dpkg 2>/dev/null; sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock 2>/dev/null" || true
            sleep 2
        fi
    done

    for host in "${ALL_HOSTS[@]}"; do
        log_info "Installing docker.io and ceph-common on $host..."
        # First fix any dpkg interruption issues
        ssh "$host" "sudo dpkg --configure -a 2>/dev/null" || true

        # Retry logic for installation
        local max_retries=3
        local retry=0
        local success=false
        while [ $retry -lt $max_retries ]; do
            if ssh "$host" "sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io ceph-common" 2>/dev/null; then
                success=true
                break
            fi
            retry=$((retry + 1))
            log_warn "Retry $retry/$max_retries for $host..."
            # Fix dpkg again before retry
            ssh "$host" "sudo dpkg --configure -a 2>/dev/null" || true
            sleep 10
        done

        # Verify docker is actually installed
        if ! ssh "$host" "which docker > /dev/null 2>&1"; then
            log_error "Docker installation failed on $host!"
            exit 1
        fi
    done

    log_info "Installing cephadm on $BOOTSTRAP_HOST..."
    # Wait for apt on bootstrap host again
    wait_for_apt "$BOOTSTRAP_HOST" || true

    # Try apt first, then download directly if apt fails
    run_on_host "$BOOTSTRAP_HOST" "
        if ! which cephadm > /dev/null 2>&1; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cephadm || {
                echo 'apt install failed, downloading cephadm directly...'
                curl --silent --remote-name --location https://download.ceph.com/rpm-squid/el9/noarch/cephadm
                chmod +x cephadm
                sudo mv cephadm /usr/sbin/cephadm
            }
        fi
        # Verify cephadm is installed
        which cephadm && (cephadm version || true)
    "

    # Verify cephadm is actually available
    if ! run_on_host "$BOOTSTRAP_HOST" "which cephadm > /dev/null 2>&1"; then
        log_error "cephadm installation failed!"
        exit 1
    fi

    log_info "Phase 1 complete: Prerequisites installed"
}

# ============================================================================
# PHASE 2: Bootstrap Ceph cluster
# ============================================================================
phase2_bootstrap() {
    log_info "=== PHASE 2: Bootstrapping Ceph cluster ==="

    # Check if already bootstrapped
    if run_on_host "$BOOTSTRAP_HOST" "sudo test -f /etc/ceph/ceph.conf" 2>/dev/null; then
        log_warn "Ceph already bootstrapped on $BOOTSTRAP_HOST, skipping bootstrap"
        return 0
    fi

    log_info "Bootstrapping Ceph on $BOOTSTRAP_HOST ($BOOTSTRAP_IP)..."
    run_on_host "$BOOTSTRAP_HOST" "sudo cephadm bootstrap --mon-ip $BOOTSTRAP_IP --skip-monitoring-stack"

    log_info "Phase 2 complete: Ceph bootstrapped"
}

# ============================================================================
# PHASE 3: Distribute SSH keys to all hosts
# ============================================================================
phase3_distribute_keys() {
    log_info "=== PHASE 3: Distributing Ceph SSH keys ==="

    # Get the ceph public key
    CEPH_PUBKEY=$(run_on_host "$BOOTSTRAP_HOST" "sudo cat /etc/ceph/ceph.pub")

    for host in "${ALL_HOSTS[@]}"; do
        if [ "$host" != "$BOOTSTRAP_HOST" ]; then
            log_info "Adding Ceph SSH key to $host..."
            run_on_host "$host" "grep -qF '$CEPH_PUBKEY' /root/.ssh/authorized_keys 2>/dev/null || echo '$CEPH_PUBKEY' | sudo tee -a /root/.ssh/authorized_keys > /dev/null"
        fi
    done

    log_info "Phase 3 complete: SSH keys distributed"
}

# ============================================================================
# PHASE 4: Add hosts to Ceph cluster
# ============================================================================
phase4_add_hosts() {
    log_info "=== PHASE 4: Adding hosts to Ceph cluster ==="

    # Add all hosts
    for i in "${!ALL_HOSTS[@]}"; do
        host="${ALL_HOSTS[$i]}"
        if [ "$host" == "hypervisor-1" ]; then
            ip="${CONTROL_IPS[0]}"
        elif [ "$host" == "hypervisor-2" ]; then
            ip="${CONTROL_IPS[1]}"
        elif [ "$host" == "hypervisor-3" ]; then
            ip="${CONTROL_IPS[2]}"
        elif [ "$host" == "hypervisor-4" ]; then
            ip="${OSD_IPS[0]}"
        else
            ip="${OSD_IPS[1]}"
        fi

        log_info "Adding $host ($ip) to cluster..."
        run_ceph_cmd ceph orch host add "$host" "$ip" 2>/dev/null || log_warn "$host may already be added"
    done

    # Add labels to control plane hosts
    for host in "${CONTROL_HOSTS[@]}"; do
        log_info "Labeling $host as 'control'..."
        run_ceph_cmd ceph orch host label add "$host" control 2>/dev/null || true
    done

    # Add labels to OSD hosts
    for host in "${OSD_HOSTS[@]}"; do
        log_info "Labeling $host as 'osd'..."
        run_ceph_cmd ceph orch host label add "$host" osd 2>/dev/null || true
    done

    log_info "Phase 4 complete: Hosts added and labeled"
}

# ============================================================================
# PHASE 5: Deploy MON and MGR on control plane
# ============================================================================
phase5_deploy_mon_mgr() {
    log_info "=== PHASE 5: Deploying MON and MGR on control plane ==="

    log_info "Deploying MON daemons on control plane..."
    run_ceph_cmd ceph orch apply mon --placement="label:control"

    log_info "Deploying MGR daemons on control plane..."
    run_ceph_cmd ceph orch apply mgr --placement="label:control"

    # Wait for MON/MGR to be deployed
    sleep 10
    wait_for_health 30

    log_info "Phase 5 complete: MON and MGR deployed"
}

# ============================================================================
# PHASE 6: Deploy OSDs on data plane
# ============================================================================
phase6_deploy_osds() {
    log_info "=== PHASE 6: Deploying OSDs on data plane ==="

    # Create OSD spec file - write to cephadm-accessible location
    OSD_SPEC=$(cat <<'EOF'
service_type: osd
service_id: osd-data
placement:
  label: osd
spec:
  data_devices:
    all: true
EOF
)

    # Apply OSD spec - pipe directly into cephadm shell
    log_info "Applying OSD specification..."
    echo "$OSD_SPEC" | ssh "$BOOTSTRAP_HOST" "sudo cephadm shell -- ceph orch apply -i -"

    # Wait for OSDs to come up (this can take a while)
    log_info "Waiting for OSDs to deploy (this may take a few minutes)..."
    sleep 30

    local max_attempts=60
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        OSD_COUNT=$(run_ceph_cmd ceph osd stat 2>/dev/null | grep -oP '\d+(?= osds)' || echo "0")
        if [ "$OSD_COUNT" -gt 0 ]; then
            log_info "Found $OSD_COUNT OSD(s) deployed"
            break
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 10
    done

    wait_for_health 60

    log_info "Phase 6 complete: OSDs deployed"
}

# ============================================================================
# PHASE 7: Configure pool settings and create RBD pool
# ============================================================================
phase7_create_rbd() {
    log_info "=== PHASE 7: Configuring pools and creating RBD pool ==="

    # Set default pool size to 2 (since we have 2 OSDs)
    log_info "Setting default pool size to 2 for 2-OSD cluster..."
    run_ceph_cmd ceph config set global osd_pool_default_size 2
    run_ceph_cmd ceph config set global osd_pool_default_min_size 1

    # Set existing pools to size 2
    log_info "Configuring existing pools with size=2..."
    for pool in $(run_ceph_cmd ceph osd pool ls 2>/dev/null); do
        run_ceph_cmd ceph osd pool set "$pool" size 2 --yes-i-really-mean-it 2>/dev/null || true
        run_ceph_cmd ceph osd pool set "$pool" min_size 1 2>/dev/null || true
    done

    # Check if pool exists
    if run_ceph_cmd ceph osd pool ls 2>/dev/null | grep -q "^${RBD_POOL}$"; then
        log_warn "Pool $RBD_POOL already exists, skipping creation"
    else
        log_info "Creating RBD pool: $RBD_POOL..."
        run_ceph_cmd ceph osd pool create "$RBD_POOL" 32
        run_ceph_cmd ceph osd pool application enable "$RBD_POOL" rbd
        run_ceph_cmd rbd pool init "$RBD_POOL"
    fi

    # Create RBD user
    log_info "Creating RBD user: client.$RBD_USER..."
    run_ceph_cmd ceph auth get-or-create client.$RBD_USER \
        mon "'profile rbd'" \
        osd "'profile rbd pool=$RBD_POOL'" \
        mgr "'profile rbd pool=$RBD_POOL'"

    log_info "Phase 7 complete: RBD pool and user created"
}

# ============================================================================
# PHASE 8: Deploy RadosGW (S3 Gateway)
# ============================================================================
phase8_deploy_rgw() {
    log_info "=== PHASE 8: Deploying RadosGW (S3 Gateway) ==="

    # Check if RGW is already running
    if run_ceph_cmd ceph orch ps --daemon-type rgw 2>/dev/null | grep -q "running"; then
        log_warn "RGW already running, skipping deployment"
    else
        log_info "Deploying RGW on OSD hosts (port $RGW_PORT)..."
        # Create RGW spec and apply via stdin
        cat <<EOF | ssh "$BOOTSTRAP_HOST" "sudo cephadm shell -- ceph orch apply -i -"
service_type: rgw
service_id: s3-gw
placement:
  hosts:
    - hypervisor-4
    - hypervisor-5
spec:
  rgw_frontend_port: $RGW_PORT
EOF

        # Wait for RGW to come up
        log_info "Waiting for RGW to deploy..."
        sleep 30

        # Check RGW status
        local max_attempts=30
        local attempt=0
        while [ $attempt -lt $max_attempts ]; do
            if run_ceph_cmd ceph orch ps --daemon-type rgw 2>/dev/null | grep -q "running"; then
                log_info "RGW is running"
                break
            fi
            attempt=$((attempt + 1))
            echo -n "."
            sleep 5
        done
    fi

    # Create S3 user (idempotent - will fail silently if exists)
    log_info "Creating S3 user: $RGW_USER..."
    ssh "$BOOTSTRAP_HOST" "sudo cephadm shell -- radosgw-admin user create --uid=$RGW_USER --display-name='S3_User'" 2>&1 || true

    # Get user info - run command and capture full output
    log_info "Extracting S3 credentials..."
    local USER_INFO
    USER_INFO=$(ssh "$BOOTSTRAP_HOST" "sudo cephadm shell -- radosgw-admin user info --uid=$RGW_USER" 2>&1) || true

    # Debug: show if we got user info
    if echo "$USER_INFO" | grep -q "access_key"; then
        log_info "User info retrieved successfully"
    else
        log_error "Failed to get user info. Output: $USER_INFO"
        return 1
    fi

    # Extract keys using sed
    ACCESS_KEY=$(echo "$USER_INFO" | sed -n 's/.*"access_key":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    SECRET_KEY=$(echo "$USER_INFO" | sed -n 's/.*"secret_key":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

    if [ -n "$ACCESS_KEY" ] && [ -n "$SECRET_KEY" ]; then
        log_info "S3 credentials:"
        echo "  Access Key: $ACCESS_KEY"
        echo "  Secret Key: $SECRET_KEY"

        # Save credentials to file on bootstrap host using echo (more reliable than heredoc over ssh)
        ssh "$BOOTSTRAP_HOST" "echo 'S3 User Credentials
===================
Access Key: $ACCESS_KEY
Secret Key: $SECRET_KEY
Endpoint: http://192.168.10.14:$RGW_PORT or http://192.168.10.15:$RGW_PORT' | sudo tee /root/s3-credentials.txt > /dev/null"

        log_info "Credentials saved to $BOOTSTRAP_HOST:/root/s3-credentials.txt"
    else
        log_error "Could not extract S3 credentials!"
        log_info "ACCESS_KEY='$ACCESS_KEY' SECRET_KEY='$SECRET_KEY'"
        log_info "You can get them manually with: sudo cephadm shell -- radosgw-admin user info --uid=$RGW_USER"
        return 1
    fi

    log_info "Phase 8 complete: RadosGW deployed"
}

# ============================================================================
# PHASE 9: Export configs for OpenStack integration
# ============================================================================
phase9_export_configs() {
    log_info "=== PHASE 9: Exporting configs for OpenStack integration ==="

    # Get FSID
    FSID=$(run_ceph_cmd ceph fsid)
    log_info "Cluster FSID: $FSID"

    # Export ceph.conf to host
    log_info "Exporting ceph.conf to $BOOTSTRAP_HOST:/etc/ceph/ceph.conf..."
    run_ceph_cmd ceph config generate-minimal-conf | ssh "$BOOTSTRAP_HOST" "sudo tee /etc/ceph/ceph.conf > /dev/null"

    # Export admin keyring
    log_info "Exporting admin keyring..."
    run_ceph_cmd ceph auth get client.admin | ssh "$BOOTSTRAP_HOST" "sudo tee /etc/ceph/ceph.client.admin.keyring > /dev/null"
    ssh "$BOOTSTRAP_HOST" "sudo chmod 600 /etc/ceph/ceph.client.admin.keyring"

    # Export RBD user keyring
    log_info "Exporting $RBD_USER keyring..."
    run_ceph_cmd ceph auth get client.$RBD_USER | ssh "$BOOTSTRAP_HOST" "sudo tee /etc/ceph/ceph.client.$RBD_USER.keyring > /dev/null"
    ssh "$BOOTSTRAP_HOST" "sudo chmod 600 /etc/ceph/ceph.client.$RBD_USER.keyring"

    log_info "Phase 9 complete: Configs exported"
}

# ============================================================================
# PHASE 10: Verification tests
# ============================================================================
phase10_verify() {
    log_info "=== PHASE 10: Running verification tests ==="

    echo ""
    log_info "--- Test 1: Cluster Health ---"
    run_ceph_cmd ceph -s

    echo ""
    log_info "--- Test 2: OSD Status ---"
    run_ceph_cmd ceph osd tree

    echo ""
    log_info "--- Test 3: Pool List ---"
    run_ceph_cmd ceph osd pool ls detail

    echo ""
    log_info "--- Test 4: RBD Pool Test ---"
    TEST_IMAGE="test-image-$$"
    log_info "Creating test RBD image: $TEST_IMAGE..."
    run_ceph_cmd rbd create --size 100 $RBD_POOL/$TEST_IMAGE
    log_info "Listing RBD images..."
    run_ceph_cmd rbd ls $RBD_POOL
    log_info "Getting image info..."
    run_ceph_cmd rbd info $RBD_POOL/$TEST_IMAGE
    log_info "Removing test image..."
    run_ceph_cmd rbd rm $RBD_POOL/$TEST_IMAGE
    log_info "RBD test passed!"

    echo ""
    log_info "--- Test 5: RadosGW Status ---"
    run_ceph_cmd ceph orch ps --daemon-type rgw

    echo ""
    log_info "--- Test 6: S3 Connectivity Test ---"
    # Test S3 endpoint from one of the OSD hosts
    if curl -s --connect-timeout 5 "http://192.168.10.14:$RGW_PORT" > /dev/null 2>&1; then
        log_info "S3 endpoint on hypervisor-4:$RGW_PORT is reachable"
    else
        log_warn "S3 endpoint on hypervisor-4:$RGW_PORT may not be ready yet"
    fi

    if curl -s --connect-timeout 5 "http://192.168.10.15:$RGW_PORT" > /dev/null 2>&1; then
        log_info "S3 endpoint on hypervisor-5:$RGW_PORT is reachable"
    else
        log_warn "S3 endpoint on hypervisor-5:$RGW_PORT may not be ready yet"
    fi

    echo ""
    log_info "--- Test 7: Host Status ---"
    run_ceph_cmd ceph orch host ls

    echo ""
    log_info "--- Test 8: Full S3 Test with AWS CLI ---"
    # Install AWS CLI on bootstrap host if not present
    log_info "Installing AWS CLI on $BOOTSTRAP_HOST..."
    ssh "$BOOTSTRAP_HOST" 'if ! which aws > /dev/null 2>&1; then
        sudo apt-get install -y -qq unzip curl
        cd /tmp
        curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip -q -o awscliv2.zip
        sudo ./aws/install --update 2>/dev/null || sudo ./aws/install 2>/dev/null
    fi'

    # Get S3 credentials from the credentials file we saved earlier
    S3_ACCESS_KEY=$(ssh "$BOOTSTRAP_HOST" "sudo grep 'Access Key' /root/s3-credentials.txt 2>/dev/null | cut -d: -f2 | tr -d ' '")
    S3_SECRET_KEY=$(ssh "$BOOTSTRAP_HOST" "sudo grep 'Secret Key' /root/s3-credentials.txt 2>/dev/null | cut -d: -f2 | tr -d ' '")

    if [ -n "$S3_ACCESS_KEY" ] && [ -n "$S3_SECRET_KEY" ]; then
        log_info "Running S3 bucket test..."
        log_info "Using Access Key: $S3_ACCESS_KEY"

        # Configure AWS credentials on bootstrap host (as root)
        ssh "$BOOTSTRAP_HOST" "sudo mkdir -p /root/.aws && echo '[ceph]
aws_access_key_id = $S3_ACCESS_KEY
aws_secret_access_key = $S3_SECRET_KEY' | sudo tee /root/.aws/credentials > /dev/null && echo '[profile ceph]
region = us-east-1' | sudo tee /root/.aws/config > /dev/null"

        # Run S3 test as root
        ssh "$BOOTSTRAP_HOST" "sudo /usr/local/bin/aws --endpoint-url http://192.168.10.14:$RGW_PORT --profile ceph s3 mb s3://ceph-test-bucket" 2>&1 || true
        log_info "Created test bucket"

        ssh "$BOOTSTRAP_HOST" "echo 'Hello from Ceph S3 automated test!' | sudo tee /tmp/s3-test.txt > /dev/null"
        ssh "$BOOTSTRAP_HOST" "sudo /usr/local/bin/aws --endpoint-url http://192.168.10.14:$RGW_PORT --profile ceph s3 cp /tmp/s3-test.txt s3://ceph-test-bucket/test.txt" 2>&1
        log_info "Uploaded test file"

        log_info "Listing bucket contents:"
        ssh "$BOOTSTRAP_HOST" "sudo /usr/local/bin/aws --endpoint-url http://192.168.10.14:$RGW_PORT --profile ceph s3 ls s3://ceph-test-bucket/" 2>&1

        log_info "Downloading and verifying:"
        ssh "$BOOTSTRAP_HOST" "sudo /usr/local/bin/aws --endpoint-url http://192.168.10.14:$RGW_PORT --profile ceph s3 cp s3://ceph-test-bucket/test.txt /tmp/s3-download.txt" 2>&1
        ssh "$BOOTSTRAP_HOST" "cat /tmp/s3-download.txt"

        log_info "Cleaning up test bucket..."
        ssh "$BOOTSTRAP_HOST" "sudo /usr/local/bin/aws --endpoint-url http://192.168.10.14:$RGW_PORT --profile ceph s3 rm s3://ceph-test-bucket/test.txt" 2>&1 || true
        ssh "$BOOTSTRAP_HOST" "sudo /usr/local/bin/aws --endpoint-url http://192.168.10.14:$RGW_PORT --profile ceph s3 rb s3://ceph-test-bucket" 2>&1 || true

        log_info "S3 test passed!"
    else
        log_warn "Could not retrieve S3 credentials for full test"
    fi

    echo ""
    log_info "=== ALL VERIFICATION TESTS COMPLETE ==="
}

# ============================================================================
# Main execution
# ============================================================================
main() {
    echo "============================================================"
    echo "       Ceph Cluster One-Click Setup"
    echo "============================================================"
    echo ""
    echo "Control Plane: ${CONTROL_HOSTS[*]}"
    echo "Data Plane:    ${OSD_HOSTS[*]}"
    echo ""

    phase0_fix_ssh_keys
    phase1_prerequisites
    phase2_bootstrap
    phase3_distribute_keys
    phase4_add_hosts
    phase5_deploy_mon_mgr
    phase6_deploy_osds
    phase7_create_rbd
    phase8_deploy_rgw
    phase9_export_configs
    phase10_verify

    echo ""
    echo "============================================================"
    log_info "Ceph cluster setup complete!"
    echo "============================================================"
    echo ""
    echo "Next steps:"
    echo "  1. For S3 access, AWS CLI is installed on $BOOTSTRAP_HOST"
    echo "     Credentials saved at: $BOOTSTRAP_HOST:/root/s3-credentials.txt"
    echo "     AWS config at: $BOOTSTRAP_HOST:~/.aws/"
    echo ""
    echo "  2. For OpenStack integration, use configs from:"
    echo "     /etc/ceph/ceph.conf"
    echo "     /etc/ceph/ceph.client.admin.keyring"
    echo ""
    echo "  3. To check cluster status anytime:"
    echo "     ssh $BOOTSTRAP_HOST 'sudo cephadm shell -- ceph -s'"
    echo ""
    echo "  4. To use S3 from $BOOTSTRAP_HOST:"
    echo "     ssh $BOOTSTRAP_HOST"
    echo "     aws --endpoint-url http://192.168.10.14:$RGW_PORT --profile ceph s3 ls"
    echo ""
}

# Run main
main "$@"
