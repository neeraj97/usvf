ssh ubuntu@192.168.10.11 -i config/vdc-dc1/ssh-keys/id_rsa "sudo ip addr add 10.100.0.254/32 dev lo1"
ssh ubuntu@192.168.10.12 -i config/vdc-dc1/ssh-keys/id_rsa "sudo ip addr add 10.100.0.254/32 dev lo1"
ssh ubuntu@192.168.10.13 -i config/vdc-dc1/ssh-keys/id_rsa "sudo ip addr add 10.100.0.254/32 dev lo1"

-- compute and storage ----
ssh ubuntu@192.168.10.14 -i config/vdc-dc1/ssh-keys/id_rsa "sudo pvcreate /dev/vdb && sudo vgcreate cinder-volumes /dev/vdb"
ssh ubuntu@192.168.10.15 -i config/vdc-dc1/ssh-keys/id_rsa "sudo pvcreate /dev/vdb && sudo vgcreate cinder-volumes /dev/vdb"


-------------inside each Storage nodes ----------
sudo modprobe target_core_mod
sudo modprobe iscsi_target_mod
sudo modprobe tcm_loop

# Make it persistent across reboots
echo "target_core_mod" | sudo tee -a /etc/modules
echo "iscsi_target_mod" | sudo tee -a /etc/modules
echo "tcm_loop" | sudo tee -a /etc/modules

sudo apt update
sudo apt install -y open-iscsi lsscsi sg3-utils multipath-tools
sudo systemctl enable --now iscsid
sudo systemctl enable --now multipathd
