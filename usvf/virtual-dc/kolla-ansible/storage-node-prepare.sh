#!/bin/bash
set -eux
sudo pvcreate /dev/vdb && sudo vgcreate cinder-volumes /dev/vdb
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