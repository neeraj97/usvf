# Virtual DC Quick Start Guide

Get your virtual datacenter up and running in 15 minutes!

## 🚀 Fast Track Deployment

### Step 1: Install Prerequisites (5 minutes)

```bash
cd usvf/virtual-dc

# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y \
    qemu-kvm libvirt-daemon-system libvirt-clients virtinst \
    bridge-utils virt-manager iproute2 jq genisoimage

# Install yq
sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
    -O /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq

# Add user to groups
sudo usermod -aG libvirt,kvm $USER

# ⚠️ IMPORTANT: Log out and back in for group changes to take effect!
```

### Step 2: Verify Setup (1 minute)

```bash
# After logging back in
./scripts/deploy-virtual-dc.sh --validate
```

If you see ✓ for all checks, you're ready to go!

### Step 3: Choose Your Topology (1 minute)

Pick one of these pre-configured examples:

**Simple (2 hypervisors, 1 leaf)** - Perfect for learning
```bash
cp examples/simple-2node.yaml config/my-topology.yaml
```

**Standard (4 hypervisors, 2 leafs, 2 spines)** - Production-like
```bash
cp config/topology.yaml config/my-topology.yaml
```

### Step 4: Deploy! (8-12 minutes)

```bash
# Full automated deployment
./scripts/deploy-virtual-dc.sh --config config/my-topology.yaml

# Or use the default topology
./scripts/deploy-virtual-dc.sh
```

☕ Grab a coffee while the system:
- Creates management network
- Deploys hypervisor VMs
- Deploys switch VMs
- Configures BGP unnumbered
- Verifies everything

### Step 5: Access Your Infrastructure (< 1 minute)

```bash
# List all VMs
virsh list --all

# SSH into first hypervisor
ssh -i config/virtual-dc-lab-ssh-key ubuntu@192.168.100.11

# Check BGP status
ssh -i config/virtual-dc-lab-ssh-key ubuntu@192.168.100.11 \
    "sudo vtysh -c 'show bgp summary'"
```

## 🎯 What You Get

After deployment, you'll have:

✅ **Hypervisors** - KVM VMs running Ubuntu with FRRouting  
✅ **Switches** - Virtual SONiC switches in Leaf/Spine architecture  
✅ **BGP Unnumbered** - Fully configured L3 fabric  
✅ **Management Network** - L2 network for out-of-band access  
✅ **SSH Access** - Key-based authentication to all VMs  

## 📊 Quick Commands

### View Status
```bash
virsh list --all              # All VMs
virsh net-list --all          # All networks
cat config/verification-report.txt  # Deployment report
```

### Access VMs
```bash
# SSH to hypervisor
ssh -i config/virtual-dc-lab-ssh-key ubuntu@192.168.100.11

# Console access
virsh console hypervisor-1
# Press Ctrl+] to exit
```

### Check BGP
```bash
# On all hypervisors
for ip in 192.168.100.{11..14}; do
    echo "=== $ip ==="
    ssh -i config/virtual-dc-lab-ssh-key ubuntu@$ip \
        "sudo vtysh -c 'show bgp summary'" 2>/dev/null
done
```

### Cleanup
```bash
# Remove everything
for vm in $(virsh list --all --name | grep -E 'hypervisor|leaf|spine'); do
    virsh destroy $vm 2>/dev/null
    virsh undefine $vm --remove-all-storage 2>/dev/null
done

for net in $(virsh net-list --all --name | grep -E 'virtual-dc|p2p'); do
    virsh net-destroy $net 2>/dev/null
    virsh net-undefine $net 2>/dev/null
done
```

## 🔧 Troubleshooting

### Can't SSH to VMs?
```bash
# Wait for cloud-init to finish (takes 2-3 minutes after VM start)
virsh console hypervisor-1
# Check: tail -f /var/log/cloud-init.log

# Verify SSH key permissions
chmod 600 config/*-ssh-key
```

### BGP Not Working?
```bash
# SSH into hypervisor
ssh -i config/virtual-dc-lab-ssh-key ubuntu@192.168.100.11

# Check FRR status
sudo systemctl status frr

# Restart if needed
sudo systemctl restart frr

# View config
sudo vtysh -c "show running-config"
```

### VMs Not Starting?
```bash
# Check libvirt
sudo systemctl status libvirtd

# View VM logs
sudo journalctl -u libvirtd -n 50

# Try starting with console
virsh start hypervisor-1 --console
```

## 📚 Next Steps

1. **Customize Your Topology**
   - Edit `config/my-topology.yaml`
   - Add more hypervisors or switches
   - Change ASN assignments

2. **Learn BGP Configuration**
   - SSH into hypervisors
   - Use `vtysh` to interact with FRRouting
   - View BGP routes and neighbors

3. **Test Network Connectivity**
   - Ping between hypervisors
   - Trace routes through the fabric
   - Test failover scenarios

4. **Read Full Documentation**
   - [README.md](README.md) - Complete documentation
   - [USAGE_GUIDE.md](USAGE_GUIDE.md) - Detailed usage guide

## 🆘 Need Help?

- Check logs: `config/verification-report.txt`
- Enable debug: `export DEBUG=1 && ./scripts/deploy-virtual-dc.sh`
- Review module logs in the terminal output
- Consult the full documentation

## 💡 Pro Tips

1. **Start Small** - Begin with simple-2node.yaml
2. **Use Dry Run** - Test with `--dry-run` flag first
3. **Monitor Resources** - Check `htop` during deployment
4. **Save Configs** - Version control your topology.yaml
5. **Regular Cleanup** - Remove old deployments to free resources

---

**Time to First Working DC: ~15 minutes** ⚡

Happy virtual datacenter building! 🎉
