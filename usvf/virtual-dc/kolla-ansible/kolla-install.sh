#!/bin/bash
set -eux

sudo apt update
sudo apt install -y python3-dev libffi-dev gcc libssl-dev python3-venv git

# Create the virtual environment in your home directory
python3 -m venv ~/kolla-venv

# Activate the virtual environment
source ~/kolla-venv/bin/activate

# Upgrade pip to the latest version inside the venv
pip install -U pip

# Install Ansible (Version 8 or 9 is generally safe for Caracal)
pip install "ansible>=8,<10"

# Install Kolla Ansible for Caracal
pip install "kolla-ansible==18.0.0"

# change 2024.1 to 2024.2 change in below file
# nano kolla-venv/share/kolla-ansible/requirements.yml
sed -i 's@http://2024.1@2024.2' kolla-venv/share/kolla-ansible/requirements.yml

kolla-ansible install-deps

sudo mkdir -p /etc/kolla
sudo chown $USER:$USER /etc/kolla

cp -r kolla-venv/share/kolla-ansible/etc_examples/kolla/*  /etc/kolla/

kolla-genpwd
cp ~/globals.yml /etc/kolla/
# add multinode and put your globals.yaml to /etc/kolla
kolla-ansible -i multinode bootstrap-servers
kolla-ansible -i multinode deploy
kolla-ansible -i multinode post-deploy
