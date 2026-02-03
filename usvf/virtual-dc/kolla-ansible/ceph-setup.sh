#!/bin/bash
# ============================================================
# Ceph Setup for OpenStack Integration
# Run this on a Ceph admin node (one of 192.168.10.11-13)
# ============================================================

set -e

# ========================
# Configuration
# ========================
# Pool PG numbers - adjust based on your OSD count
# Formula: (OSDs * 100) / replicas / pools
# For 5 nodes with ~3 OSDs each = 15 OSDs, replica 3 = ~100 PGs per pool
VOLUMES_PGS=128
IMAGES_PGS=64
BACKUPS_PGS=64
VMS_PGS=128

echo "============================================"
echo "Step 1: Creating Ceph Pools for OpenStack"
echo "============================================"

# Create pools
ceph osd pool create volumes $VOLUMES_PGS
ceph osd pool create images $IMAGES_PGS
ceph osd pool create backups $BACKUPS_PGS
ceph osd pool create vms $VMS_PGS

# Set pool application
ceph osd pool application enable volumes rbd
ceph osd pool application enable images rbd
ceph osd pool application enable backups rbd
ceph osd pool application enable vms rbd

# Initialize RBD pools
rbd pool init volumes
rbd pool init images
rbd pool init backups
rbd pool init vms

echo "Pools created successfully!"
ceph osd pool ls detail

echo ""
echo "============================================"
echo "Step 2: Creating Ceph Users for OpenStack"
echo "============================================"

# Glance user - read/write images pool
ceph auth get-or-create client.glance \
    mon 'profile rbd' \
    osd 'profile rbd pool=images' \
    mgr 'profile rbd pool=images'

# Cinder user - read/write volumes and vms, read images
ceph auth get-or-create client.cinder \
    mon 'profile rbd' \
    osd 'profile rbd pool=volumes, profile rbd pool=vms, profile rbd-read-only pool=images' \
    mgr 'profile rbd pool=volumes, profile rbd pool=vms'

# Cinder-backup user - read/write backups
ceph auth get-or-create client.cinder-backup \
    mon 'profile rbd' \
    osd 'profile rbd pool=backups' \
    mgr 'profile rbd pool=backups'

# Nova user - read/write vms, read volumes and images (for boot from volume, live migration)
ceph auth get-or-create client.nova \
    mon 'profile rbd' \
    osd 'profile rbd pool=vms, profile rbd pool=volumes, profile rbd-read-only pool=images' \
    mgr 'profile rbd pool=vms'

echo "Users created successfully!"
ceph auth ls | grep -E "client\.(glance|cinder|nova)"

echo ""
echo "============================================"
echo "Step 3: Exporting Keyrings"
echo "============================================"

# Export keyrings to /etc/ceph/
ceph auth get client.glance -o /etc/ceph/ceph.client.glance.keyring
ceph auth get client.cinder -o /etc/ceph/ceph.client.cinder.keyring
ceph auth get client.cinder-backup -o /etc/ceph/ceph.client.cinder-backup.keyring
ceph auth get client.nova -o /etc/ceph/ceph.client.nova.keyring

# Set proper permissions
chmod 644 /etc/ceph/ceph.client.*.keyring

echo "Keyrings exported to /etc/ceph/"
ls -la /etc/ceph/ceph.client.*.keyring

echo ""
echo "============================================"
echo "Step 4: Verify Ceph Configuration"
echo "============================================"

echo "Ceph cluster status:"
ceph -s

echo ""
echo "Ceph pools:"
ceph osd pool ls detail | grep -E "^pool"

echo ""
echo "============================================"
echo "NEXT STEPS"
echo "============================================"
echo "1. Copy ceph.conf and keyrings to your Kolla deployment host:"
echo ""
echo "   DEPLOY_HOST=<your-deployment-host>"
echo "   scp /etc/ceph/ceph.conf \$DEPLOY_HOST:/etc/kolla/config/glance/"
echo "   scp /etc/ceph/ceph.conf \$DEPLOY_HOST:/etc/kolla/config/cinder/"
echo "   scp /etc/ceph/ceph.conf \$DEPLOY_HOST:/etc/kolla/config/nova/"
echo ""
echo "   scp /etc/ceph/ceph.client.glance.keyring \$DEPLOY_HOST:/etc/kolla/config/glance/"
echo "   scp /etc/ceph/ceph.client.cinder.keyring \$DEPLOY_HOST:/etc/kolla/config/cinder/cinder-volume/"
echo "   scp /etc/ceph/ceph.client.cinder-backup.keyring \$DEPLOY_HOST:/etc/kolla/config/cinder/cinder-backup/"
echo "   scp /etc/ceph/ceph.client.nova.keyring \$DEPLOY_HOST:/etc/kolla/config/nova/"
echo "   scp /etc/ceph/ceph.client.cinder.keyring \$DEPLOY_HOST:/etc/kolla/config/nova/"
echo ""
echo "2. Run kolla-ansible deploy!"
echo ""
