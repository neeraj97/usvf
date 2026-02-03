# One-Click OpenStack Deployment with Ceph Backend

Complete OpenStack + Ceph deployment in 30-45 minutes with a single command.

## Quick Start

**Prerequisites:**
- 5 Ubuntu 22.04 hypervisors (fresh installation)
- SSH access from deployment host to all hypervisors
- Run from hypervisor-1 or external deployment host

**Deploy everything:**
```bash
cd /path/to/usvf/kolla-ansible
bash deploy-all.sh
```

That's it! The script will automatically:
1. Install Kolla-Ansible prerequisites
2. Configure OpenStack settings
3. Bootstrap all nodes (Docker setup)
4. Deploy Ceph cluster (MON, MGR, OSD, RadosGW)
5. Deploy OpenStack services
6. Verify the deployment

## Architecture

- **Control Plane:** hypervisor-1,2,3 (192.168.10.11-13)
  - OpenStack APIs (Keystone, Nova, Glance, Cinder, Neutron, Horizon, Heat)
  - Ceph MON/MGR daemons

- **Compute/Storage:** hypervisor-4,5 (192.168.10.14-15)
  - Nova compute + Cinder volume
  - Ceph OSD daemons

- **VIP:** 10.100.0.254 (Anycast on all controllers)
- **Storage Backend:** Ceph for all OpenStack storage (images, volumes, ephemeral, backups)

## Deployment Options

### Option 1: deploy-all.sh (Recommended - Granular Control)

9-phase deployment with individual phase execution:

| Phase | Description |
|-------|-------------|
| phase1 | Install Kolla-Ansible prerequisites |
| phase2 | Create base Kolla configs |
| phase3 | Bootstrap OpenStack nodes (Docker setup) |
| phase4 | Deploy Ceph cluster |
| phase5 | Install Ceph client packages |
| phase6 | Create OpenStack Ceph users (glance, cinder, nova, etc.) |
| phase7 | Distribute Ceph configs to Kolla directories |
| phase8 | Deploy OpenStack services |
| phase9 | Verify deployment |

**Run all phases:**
```bash
bash deploy-all.sh
```

**Run specific phase:**
```bash
bash deploy-all.sh phase4  # Just deploy Ceph
bash deploy-all.sh phase8  # Just deploy OpenStack (requires existing Ceph)
```

## Manual Component Deployment

**Ceph only:**
```bash
cd /path/to/usvf/virtual-dc/scripts
bash ceph-cluster-setup.sh
```

**OpenStack only (requires existing Ceph):**
```bash
cd /path/to/usvf/kolla-ansible
bash openstack-deploy.sh install      # Install kolla-ansible
bash openstack-deploy.sh configs      # Generate configs
bash openstack-deploy.sh vip          # Setup VIP
bash openstack-deploy.sh bootstrap    # Bootstrap nodes
bash openstack-deploy.sh deploy       # Deploy OpenStack
bash openstack-deploy.sh verify       # Verify deployment
```

## Access Your Cloud

**Horizon Dashboard:**
- URL: http://10.100.0.254
- Username: `admin`
- Password: `grep keystone_admin_password /etc/kolla/passwords.yml`

**OpenStack CLI:**
```bash
source /root/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh
openstack service list
openstack server create --flavor m1.small --image cirros --network demo-net test-vm
```

**Ceph CLI:**
```bash
ssh hypervisor-1
sudo cephadm shell -- ceph -s
sudo cephadm shell -- ceph osd tree
```

## Prerequisites

- Ubuntu 22.04 LTS (all hypervisors)
- Python 3.10+
- Minimum 16GB RAM per node
- Extra disk for Ceph OSDs (auto-detected on hypervisor-4,5)
- Network: 192.168.10.0/24 connectivity between nodes
- SSH key-based authentication configured

## Troubleshooting

### Docker Fails After Bootstrap
- **Cause:** Ceph containers interfering with Docker restart
- **Solution:** Scripts handle this automatically (phase3 re-adds VIP)
- **Manual:** `ssh hypervisor-X 'sudo systemctl restart docker'`

### MariaDB Connection Errors
- **Symptom:** Deploy fails with "Can't connect to server on '10.100.0.254'"
- **Solution:** Re-run `bash deploy-all.sh phase8` (auto-recovers MariaDB cluster)
- **Manual:** `kolla-ansible mariadb-recovery -i /etc/kolla/multinode`

### Ceph Not Healthy
- **Check:** `ssh hypervisor-1 'sudo cephadm shell -- ceph -s'`
- **Fix:** `ssh hypervisor-X 'sudo systemctl restart ceph.target'`

### SSH Host Key Errors After VM Rebuild
- **Symptom:** "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED"
- **Solution:** Automatic (phase1 cleans known_hosts automatically)
- **Manual:** `ssh-keygen -f ~/.ssh/known_hosts -R 192.168.10.XX`

### Container Won't Start
- **Check logs:** `docker logs <container_name>`
- **Restart:** `docker restart <container_name>`
- **View config:** `docker inspect <container_name>`

### Logs

```bash
# Deployment logs
tail -f /var/log/kolla/ansible.log

# Container logs
docker logs <container_name>

# Service logs
journalctl -xeu docker
journalctl -xeu ceph.target
```

## Configuration

Default settings (edit script variables to customize):
- **Subnet:** 192.168.10.0/24 (dc1)
- **VIP:** 10.100.0.254
- **SSH User:** ubuntu
- **Kolla Config:** /etc/kolla
- **Kolla Virtualenv:** /root/kolla-venv
- **OpenStack Version:** 2024.2 (Dalmatian)

## Documentation

- **This file:** Quick-start guide
- **[DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md):** Step-by-step manual deployment
- **[OPENSTACK-DEPLOYMENT-GUIDE.md](OPENSTACK-DEPLOYMENT-GUIDE.md):** Comprehensive educational guide with architecture details

## Features

- ✅ One-click deployment (30-45 minutes)
- ✅ Automatic retry logic for common failures
- ✅ SSH known_hosts auto-cleanup
- ✅ VIP persistence across node reboots
- ✅ Docker/Ceph conflict resolution
- ✅ MariaDB cluster auto-recovery
- ✅ Granular phase control for debugging
- ✅ Ceph backend for all storage
- ✅ OVN networking with BGP
