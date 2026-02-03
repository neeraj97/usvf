#!/bin/bash

scp -i config/vdc-dc1/ssh-keys/id_rsa config/vdc-dc1/ssh-keys/id_rsa ubuntu@192.168.10.11:~/.ssh/
scp -i config/vdc-dc1/ssh-keys/id_rsa multinode ubuntu@192.168.10.11:~/
scp -i config/vdc-dc1/ssh-keys/id_rsa globals.yml ubuntu@192.168.10.11:~/

scp -i config/vdc-dc1/ssh-keys/id_rsa ./kolla-ansible/control-plane-prepare.sh ubuntu@192.168.10.11:~/
scp -i config/vdc-dc1/ssh-keys/id_rsa ./kolla-ansible/control-plane-prepare.sh ubuntu@192.168.10.12:~/
scp -i config/vdc-dc1/ssh-keys/id_rsa ./kolla-ansible/control-plane-prepare.sh ubuntu@192.168.10.13:~/
scp -i config/vdc-dc1/ssh-keys/id_rsa ./kolla-ansible/storage-plane-prepare.sh ubuntu@192.168.10.14:~/
scp -i config/vdc-dc1/ssh-keys/id_rsa ./kolla-ansible/storage-plane-prepare.sh ubuntu@192.168.10.15:~/

ssh ubuntu@192.168.10.11 -i config/vdc-dc1/ssh-keys/id_rsa "sudo ~/control-plane-prepare.sh"
ssh ubuntu@192.168.10.12 -i config/vdc-dc1/ssh-keys/id_rsa "sudo ~/control-plane-prepare.sh"
ssh ubuntu@192.168.10.13 -i config/vdc-dc1/ssh-keys/id_rsa "sudo ~/control-plane-prepare.sh"

ssh ubuntu@192.168.10.14 -i config/vdc-dc1/ssh-keys/id_rsa "sudo ~/storage-plane-prepare.sh"
ssh ubuntu@192.168.10.15 -i config/vdc-dc1/ssh-keys/id_rsa "sudo ~/storage-plane-prepare.sh"
