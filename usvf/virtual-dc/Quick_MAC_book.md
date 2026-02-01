# Virtual DC Quick Start Guide for MAC book

## Setup Colima
```bash
brew install colima

colima start --cpu 4 --memory 8

colima ssh
```

## Inside Colima
## Setup VDC (Virtual DataCentre)
```bash
sudo su
cd ~/
sudo apt update

chmod a+x ~/

git clone https://github.com/neeraj97/usvf

cd usvf/usvf/virtual-dc/

./scripts/deploy-virtual-dc.sh --check-prereqs
```

## Working with VDC (Virtual DataCentre)
```bash
# For creating VDC
./scripts/vdc-manager.sh create --name dc3 --config config/topology.yaml

./scripts/vdc-manager.sh status --name dc3

ssh ubuntu@{mgt-ip-from-above-command} -i config/vdc-dc1/ssh-keys/id_rsa

# For Destroying VDC
./scripts/vdc-manager.sh destroy --name dc3 #to destroy
```

## Setting up Openstack with Kolla ansible
