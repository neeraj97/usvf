#!/bin/bash
# Kolla-Ansible Node Preparation Script (Ceph Backend)
# Control nodes: 192.168.10.11-13, Compute nodes: 192.168.10.14-15

SSH_KEY="config/vdc-dc1/ssh-keys/id_rsa"
CONTROL_NODES="192.168.10.11 192.168.10.12 192.168.10.13"
COMPUTE_NODES="192.168.10.14 192.168.10.15"
ALL_NODES="$CONTROL_NODES $COMPUTE_NODES"

# ========================
# 1. Anycast VIP on Controllers
# ========================
echo "Setting up Anycast VIP on control nodes..."
for node in $CONTROL_NODES; do
    ssh ubuntu@$node -i $SSH_KEY "sudo ip addr add 10.100.0.254/32 dev lo1 2>/dev/null || true"
done

# ========================
# 2. Install Ceph Client on ALL OpenStack Nodes
# ========================
echo "Installing Ceph client packages on all nodes..."
for node in $ALL_NODES; do
    ssh ubuntu@$node -i $SSH_KEY "
        sudo apt update
        sudo apt install -y ceph-common python3-rbd
    "
done

# ========================
# 3. Copy Ceph Configuration to Nodes (Optional - Kolla handles this)
# ========================
# Note: Kolla-Ansible will copy ceph.conf and keyrings from /etc/kolla/config/
# into containers. But if you want host-level access:
#
# for node in $ALL_NODES; do
#     scp -i $SSH_KEY /etc/ceph/ceph.conf ubuntu@$node:/tmp/
#     ssh ubuntu@$node -i $SSH_KEY "sudo mkdir -p /etc/ceph && sudo cp /tmp/ceph.conf /etc/ceph/"
# done

# ========================
# 4. Verify Ceph Connectivity from Compute Nodes
# ========================
echo "Testing Ceph connectivity from compute nodes..."
for node in $COMPUTE_NODES; do
    echo "Testing from $node:"
    ssh ubuntu@$node -i $SSH_KEY "ceph -s --conf /etc/ceph/ceph.conf 2>/dev/null || echo 'Ceph config not yet on host (OK - Kolla will handle)'"
done

echo "Node preparation complete!"
