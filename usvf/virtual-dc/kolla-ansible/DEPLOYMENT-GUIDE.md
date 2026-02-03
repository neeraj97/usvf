# OpenStack Deployment with Kolla-Ansible + Ceph Backend

## Complete Step-by-Step Guide

This guide documents all commands executed for deploying OpenStack 2024.2 (Dalmatian) with Kolla-Ansible using an existing Ceph cluster as the storage backend.

---

## Infrastructure Overview

| Role | Hostname | IP Address | Services |
|------|----------|------------|----------|
| Control + Ceph MON | hypervisor-1 | 192.168.10.11 | OpenStack Control Plane, Ceph MON/MGR |
| Control + Ceph MON | hypervisor-2 | 192.168.10.12 | OpenStack Control Plane, Ceph MON/MGR |
| Control + Ceph MON | hypervisor-3 | 192.168.10.13 | OpenStack Control Plane, Ceph MON/MGR |
| Compute + Ceph OSD | hypervisor-4 | 192.168.10.14 | Nova Compute, Cinder Volume, Ceph OSD |
| Compute + Ceph OSD | hypervisor-5 | 192.168.10.15 | Nova Compute, Cinder Volume, Ceph OSD |

**Deployment Host:** hypervisor-1 (192.168.10.11)
**VIP Address:** 10.100.0.254 (Anycast on controller loopbacks)

---

## Phase 1: Prepare Ceph Cluster for OpenStack

### 1.1 Create Ceph Pools

Run on hypervisor-1 (Ceph admin node):

```bash
# Increase PG limit for small cluster
sudo ceph config set global mon_max_pg_per_osd 500

# Create OpenStack pools
sudo ceph osd pool create volumes 32
sudo ceph osd pool create images 16
sudo ceph osd pool create backups 16
sudo ceph osd pool create vms 32

# Set pool size to 2 (for 2-OSD cluster)
sudo ceph osd pool set volumes size 2
sudo ceph osd pool set images size 2
sudo ceph osd pool set backups size 2
sudo ceph osd pool set vms size 2

sudo ceph osd pool set volumes min_size 1
sudo ceph osd pool set images min_size 1
sudo ceph osd pool set backups min_size 1
sudo ceph osd pool set vms min_size 1

# Enable RBD application
sudo ceph osd pool application enable volumes rbd
sudo ceph osd pool application enable images rbd
sudo ceph osd pool application enable backups rbd
sudo ceph osd pool application enable vms rbd

# Initialize RBD pools
sudo rbd pool init volumes
sudo rbd pool init images
sudo rbd pool init backups
sudo rbd pool init vms
```

### 1.2 Create Ceph Users for OpenStack

```bash
# Glance user
sudo ceph auth get-or-create client.glance \
    mon 'profile rbd' \
    osd 'profile rbd pool=images' \
    mgr 'profile rbd pool=images'

# Cinder user
sudo ceph auth get-or-create client.cinder \
    mon 'profile rbd' \
    osd 'profile rbd pool=volumes, profile rbd pool=vms, profile rbd-read-only pool=images' \
    mgr 'profile rbd pool=volumes, profile rbd pool=vms'

# Cinder-backup user
sudo ceph auth get-or-create client.cinder-backup \
    mon 'profile rbd' \
    osd 'profile rbd pool=backups' \
    mgr 'profile rbd pool=backups'

# Nova user
sudo ceph auth get-or-create client.nova \
    mon 'profile rbd' \
    osd 'profile rbd pool=vms, profile rbd pool=volumes, profile rbd-read-only pool=images' \
    mgr 'profile rbd pool=vms'
```

### 1.3 Export Keyrings

```bash
sudo ceph auth get client.glance -o /etc/ceph/ceph.client.glance.keyring
sudo ceph auth get client.cinder -o /etc/ceph/ceph.client.cinder.keyring
sudo ceph auth get client.cinder-backup -o /etc/ceph/ceph.client.cinder-backup.keyring
sudo ceph auth get client.nova -o /etc/ceph/ceph.client.nova.keyring

sudo chmod 644 /etc/ceph/ceph.client.*.keyring
```

---

## Phase 2: Install Kolla-Ansible on Deployment Host

### 2.1 Install Dependencies

```bash
sudo apt update
sudo apt install -y python3-dev libffi-dev gcc libssl-dev python3-venv git
```

### 2.2 Create Virtual Environment and Install Kolla-Ansible

```bash
python3 -m venv ~/kolla-venv
source ~/kolla-venv/bin/activate

pip install -U pip
pip install "ansible>=8,<10"
pip install "kolla-ansible>=19.0.0,<20.0.0"  # 19.x = OpenStack 2024.2
```

### 2.3 Install Kolla-Ansible Dependencies

```bash
source ~/kolla-venv/bin/activate
kolla-ansible install-deps
```

---

## Phase 3: Configure Kolla-Ansible

### 3.1 Setup Configuration Directory

```bash
sudo mkdir -p /etc/kolla
sudo chown $USER:$USER /etc/kolla
cp -r ~/kolla-venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
```

### 3.2 Generate Passwords

```bash
source ~/kolla-venv/bin/activate
kolla-genpwd
```

### 3.3 Create globals.yml

Create `/etc/kolla/globals.yml`:

```yaml
---
# ========================
# 1. Base Setup
# ========================
kolla_base_distro: "ubuntu"
kolla_install_type: "source"
openstack_release: "2024.2"

# ========================
# 2. Networking (Underlay)
# ========================
kolla_internal_vip_address: "10.100.0.254"
enable_keepalived: "no"

api_interface_address: "{{ api_ip }}"
tunnel_interface_address: "{{ tunnel_ip }}"

neutron_external_interface: "dum-ex"
network_interface: "lo1"

# ========================
# 3. OVN Configuration
# ========================
neutron_plugin_agent: "ovn"
neutron_tunnel_type: "geneve"
enable_neutron_dvr: "yes"
enable_neutron_provider_networks: "yes"
neutron_ovn_distributed_fip: "yes"

# ========================
# 4. OVN BGP AGENT
# ========================
enable_neutron_bgp_dragent: "no"
enable_ovn_bgp_agent: "yes"
ovn_bgp_agent_driver: "nb_ovn_bgp_driver"

# ========================
# 5. FRR Handling
# ========================
enable_frr: "no"

# ========================
# 6. Core Services
# ========================
enable_horizon: "yes"
enable_heat: "yes"
enable_fluentd: "yes"
enable_cinder: "yes"

# ========================
# 7. Ceph Configuration (External Cluster)
# ========================
# Glance
glance_backend_ceph: "yes"
glance_backend_file: "no"
ceph_glance_keyring: "ceph.client.glance.keyring"
ceph_glance_user: "glance"
ceph_glance_pool_name: "images"

# Cinder
enable_cinder_backend_lvm: "no"
cinder_backend_ceph: "yes"
ceph_cinder_keyring: "ceph.client.cinder.keyring"
ceph_cinder_user: "cinder"
ceph_cinder_pool_name: "volumes"

# Cinder Backup
cinder_backup_driver: "ceph"
ceph_cinder_backup_keyring: "ceph.client.cinder-backup.keyring"
ceph_cinder_backup_user: "cinder-backup"
ceph_cinder_backup_pool_name: "backups"

# Nova
nova_backend_ceph: "yes"
ceph_nova_keyring: "ceph.client.nova.keyring"
ceph_nova_user: "nova"
ceph_nova_pool_name: "vms"

# Cinder HA Cluster Name (required for multiple cinder-volume)
cinder_cluster_name: "ceph-cluster"
```

### 3.4 Create Multinode Inventory

Create `/etc/kolla/multinode` with proper SSH key configuration:

```ini
[control]
control01 ansible_host=192.168.10.11 api_ip=10.1.0.1 tunnel_ip=10.1.0.1 ansible_user=ubuntu ansible_ssh_private_key_file=/home/ubuntu/.ssh/kolla-keys/id_rsa
control02 ansible_host=192.168.10.12 api_ip=10.1.0.2 tunnel_ip=10.1.0.2 ansible_user=ubuntu ansible_ssh_private_key_file=/home/ubuntu/.ssh/kolla-keys/id_rsa
control03 ansible_host=192.168.10.13 api_ip=10.1.0.3 tunnel_ip=10.1.0.3 ansible_user=ubuntu ansible_ssh_private_key_file=/home/ubuntu/.ssh/kolla-keys/id_rsa

[network]
control01
control02
control03

[compute]
compute01 ansible_host=192.168.10.14 api_ip=10.1.0.4 tunnel_ip=10.1.0.4 ansible_user=ubuntu ansible_ssh_private_key_file=/home/ubuntu/.ssh/kolla-keys/id_rsa
compute02 ansible_host=192.168.10.15 api_ip=10.1.0.5 tunnel_ip=10.1.0.5 ansible_user=ubuntu ansible_ssh_private_key_file=/home/ubuntu/.ssh/kolla-keys/id_rsa

[monitoring]
control01

[storage]
compute01
compute02

[deployment]
localhost ansible_connection=local

# ... (rest of inventory groups)
```

---

## Phase 4: Setup Ceph Configuration for Kolla

### 4.1 Create Config Directories

```bash
mkdir -p /etc/kolla/config/glance
mkdir -p /etc/kolla/config/cinder/cinder-volume
mkdir -p /etc/kolla/config/cinder/cinder-backup
mkdir -p /etc/kolla/config/nova
```

### 4.2 Create ceph.conf (IMPORTANT: No leading spaces!)

```bash
cat > /etc/kolla/config/glance/ceph.conf << 'EOF'
[global]
fsid = be49e368-fc70-11f0-9d83-525400dc495d
mon_host = [v2:192.168.10.11:3300/0,v1:192.168.10.11:6789/0] [v2:192.168.10.12:3300/0,v1:192.168.10.12:6789/0] [v2:192.168.10.13:3300/0,v1:192.168.10.13:6789/0]
EOF

cp /etc/kolla/config/glance/ceph.conf /etc/kolla/config/cinder/ceph.conf
cp /etc/kolla/config/glance/ceph.conf /etc/kolla/config/nova/ceph.conf
```

### 4.3 Copy Keyrings (IMPORTANT: Rename with ceph. prefix!)

**TODO: This needs to be fixed!** Kolla expects keyring files named with `ceph.` prefix:

```bash
# Copy keyrings with correct naming for Kolla
sudo cp /etc/ceph/ceph.client.glance.keyring /etc/kolla/config/glance/ceph.ceph.client.glance.keyring
sudo cp /etc/ceph/ceph.client.cinder.keyring /etc/kolla/config/cinder/cinder-volume/ceph.ceph.client.cinder.keyring
sudo cp /etc/ceph/ceph.client.cinder-backup.keyring /etc/kolla/config/cinder/cinder-backup/ceph.ceph.client.cinder-backup.keyring
sudo cp /etc/ceph/ceph.client.nova.keyring /etc/kolla/config/nova/ceph.ceph.client.nova.keyring
sudo cp /etc/ceph/ceph.client.cinder.keyring /etc/kolla/config/nova/ceph.ceph.client.cinder.keyring

sudo chown -R ubuntu:ubuntu /etc/kolla/config
```

---

## Phase 5: Prepare All Nodes

### 5.1 Setup SSH Keys on Deployment Host

```bash
# Copy SSH keys to deployment host
mkdir -p ~/.ssh/kolla-keys
# (Copy the SSH private key that can access all nodes)
chmod 600 ~/.ssh/kolla-keys/id_rsa
```

### 5.2 Test Ansible Connectivity

```bash
source ~/kolla-venv/bin/activate
ansible -i /etc/kolla/multinode all -m ping
```

### 5.3 Setup Anycast VIP on Control Nodes

```bash
source ~/kolla-venv/bin/activate
ansible -i /etc/kolla/multinode control -b -m shell -a "ip addr add 10.100.0.254/32 dev lo1 2>/dev/null || true"
```

### 5.4 Install ceph-common on All Nodes

```bash
source ~/kolla-venv/bin/activate
ansible -i /etc/kolla/multinode baremetal -b -m apt -a "name=ceph-common,python3-rbd state=present update_cache=yes"
```

---

## Phase 6: Deploy OpenStack

### 6.1 Bootstrap Servers

```bash
source ~/kolla-venv/bin/activate
kolla-ansible bootstrap-servers -i /etc/kolla/multinode
```

### 6.2 Run Prechecks

```bash
source ~/kolla-venv/bin/activate
kolla-ansible prechecks -i /etc/kolla/multinode
```

### 6.3 Deploy OpenStack

```bash
source ~/kolla-venv/bin/activate
kolla-ansible deploy -i /etc/kolla/multinode
```

### 6.4 Post-Deploy

```bash
source ~/kolla-venv/bin/activate
kolla-ansible post-deploy -i /etc/kolla/multinode
```

---

## Phase 7: Verification

### 7.1 Test OpenStack CLI

```bash
source /etc/kolla/admin-openrc.sh

# List services
openstack service list

# Create test volume
openstack volume create --size 1 test-volume

# Verify on Ceph
sudo rbd -p volumes ls
```

### 7.2 Test Ceph Connectivity from Containers

```bash
docker exec -it cinder_volume ceph -s
docker exec -it glance_api ceph -s
```

### 7.3 Access Horizon Dashboard

- URL: http://10.100.0.254
- Username: admin
- Password: (from /etc/kolla/passwords.yml - keystone_admin_password)

---

## Current Status / Known Issues

### Issue: Keyring File Naming
The deployment failed at the Glance configuration step because Kolla-Ansible expects keyring files to be named with the cluster name prefix:
- Expected: `ceph.ceph.client.glance.keyring`
- Found: `ceph.client.glance.keyring`

**Fix Required:** Rename all keyring files in `/etc/kolla/config/` directories with the `ceph.` prefix.

---

## Architecture Diagram

```
Control Nodes (192.168.10.11-13)    Compute Nodes (192.168.10.14-15)
┌────────────────────────────┐     ┌────────────────────────────┐
│ Keystone, Glance, Nova API │     │ Nova Compute               │
│ Cinder API, Neutron, Heat  │     │ Cinder Volume/Backup       │
│ Horizon, OVN DB, MariaDB   │     │ OVN Controller             │
│ RabbitMQ, HAProxy          │     │                            │
│ Ceph MON/MGR               │     │ Ceph OSD                   │
└────────────────────────────┘     └────────────────────────────┘
              │                                  │
              └──────────────┬───────────────────┘
                             ▼
                 ┌─────────────────────────┐
                 │   Ceph Cluster (RBD)    │
                 │ Pools: volumes, images, │
                 │        backups, vms     │
                 └─────────────────────────┘
```

---

## Files Created/Modified

| File | Location | Purpose |
|------|----------|---------|
| globals.yml | /etc/kolla/globals.yml | Main OpenStack configuration |
| multinode | /etc/kolla/multinode | Ansible inventory |
| ceph.conf | /etc/kolla/config/*/ceph.conf | Ceph cluster configuration |
| keyrings | /etc/kolla/config/*/*.keyring | Ceph authentication |

---

## Resume Tomorrow

When resuming, fix the keyring naming issue:

```bash
# On hypervisor-1
cd /etc/kolla/config

# Rename keyrings with ceph. prefix
mv glance/ceph.client.glance.keyring glance/ceph.ceph.client.glance.keyring
mv cinder/cinder-volume/ceph.client.cinder.keyring cinder/cinder-volume/ceph.ceph.client.cinder.keyring
mv cinder/cinder-backup/ceph.client.cinder-backup.keyring cinder/cinder-backup/ceph.ceph.client.cinder-backup.keyring
mv nova/ceph.client.nova.keyring nova/ceph.ceph.client.nova.keyring
mv nova/ceph.client.cinder.keyring nova/ceph.ceph.client.cinder.keyring

# Then re-run deploy
source ~/kolla-venv/bin/activate
kolla-ansible deploy -i /etc/kolla/multinode
```
