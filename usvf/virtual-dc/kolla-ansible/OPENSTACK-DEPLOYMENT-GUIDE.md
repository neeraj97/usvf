# Comprehensive OpenStack Deployment Guide with Kolla-Ansible and Ceph Backend

**Author:** Your Learning Journey
**Target Audience:** First-time OpenStack deployers who want to UNDERSTAND what they're doing
**Your Infrastructure:** 5 hypervisors, existing Ceph cluster, BGP/EVPN networking

---

## Table of Contents

1. [PART 1: Understanding the Big Picture](#part-1-understanding-the-big-picture)
   - [What is OpenStack?](#what-is-openstack)
   - [What is Kolla-Ansible?](#what-is-kolla-ansible)
   - [What is Ceph and Why Use It?](#what-is-ceph-and-why-use-it)
2. [PART 2: Your Infrastructure Architecture](#part-2-your-infrastructure-architecture)
   - [Physical Layout](#physical-layout)
   - [Network Design](#network-design)
   - [Why Anycast VIP?](#why-anycast-vip-instead-of-keepalived)
3. [PART 3: Understanding the Configuration Files](#part-3-understanding-the-configuration-files)
   - [What is globals.yml?](#what-is-globalsyml)
   - [globals.yml Line-by-Line Explanation](#globalsyml-complete-breakdown)
   - [What is the multinode Inventory File?](#what-is-the-multinode-inventory-file)
   - [multinode File Complete Explanation](#multinode-file-complete-explanation)
4. [PHASE 1: Ceph Preparation for OpenStack](#phase-1-ceph-preparation-for-openstack)
5. [PHASE 2: Deployment Host Setup](#phase-2-deployment-host-setup)
6. [PHASE 3: Copy Configuration Files](#phase-3-copy-configuration-files)
7. [PHASE 4: Ceph Config Distribution](#phase-4-ceph-config-distribution)
8. [PHASE 5: Node Preparation](#phase-5-node-preparation)
9. [PHASE 6: Pre-deployment Checks](#phase-6-pre-deployment-checks)
10. [PHASE 7: Deployment](#phase-7-deployment)
11. [PHASE 8: Post-deployment](#phase-8-post-deployment)
12. [PHASE 9: Verification & Testing](#phase-9-verification--testing)
13. [Troubleshooting Guide](#troubleshooting-guide)
14. [Quick Reference Checklist](#quick-reference-checklist)

---

# PART 1: Understanding the Big Picture

## What is OpenStack?

OpenStack is an **open-source cloud computing platform** that lets you create and manage your own private cloud infrastructure - similar to what Amazon AWS, Microsoft Azure, or Google Cloud provide, but running on your own hardware.

Think of it as the "operating system" for your data center. Just like Windows or Linux manages your laptop's resources (CPU, memory, disk), OpenStack manages your data center's resources across multiple servers.

### OpenStack Services Overview

OpenStack is **modular** - it consists of multiple independent services that work together. Here's every service you'll be deploying:

| Service Name | Project | What It Does | AWS Equivalent | Why You Need It |
|--------------|---------|--------------|----------------|-----------------|
| **Keystone** | Identity | Authentication & authorization - controls who can do what | AWS IAM | Every other service asks Keystone "is this user allowed to do this?" |
| **Glance** | Image | Stores VM templates (OS images like Ubuntu, CentOS) | AWS AMI | When you create a VM, Nova asks Glance "give me the Ubuntu image" |
| **Nova** | Compute | Creates and manages virtual machines | AWS EC2 | The core service - this is what actually runs your VMs |
| **Neutron** | Networking | Virtual networks, routers, firewalls, floating IPs | AWS VPC | VMs need networking - Neutron provides it |
| **Cinder** | Block Storage | Persistent disk volumes for VMs | AWS EBS | If a VM needs extra disk space or persistent storage |
| **Horizon** | Dashboard | Web-based management interface | AWS Console | So you don't have to use CLI for everything |
| **Heat** | Orchestration | Infrastructure as Code templates | AWS CloudFormation | Deploy complex stacks from templates |
| **Placement** | Resource Tracking | Tracks what resources are available where | Internal service | Nova asks Placement "which hypervisor has enough RAM for this VM?" |
| **OVN** | Network Controller | Software-defined networking control plane | Internal to AWS VPC | Manages virtual switches across all hosts |

### How They Work Together - A Complete Flow

When you click "Launch Instance" in Horizon:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  YOU: "Create a VM with Ubuntu, 2GB RAM, 20GB disk, on my-network"         │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  HORIZON (Dashboard) - Port 80/443                                          │
│  "User clicked Launch Instance, let me send this to the API"               │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  KEYSTONE (Identity) - Port 5000                                            │
│  "Is user 'admin' allowed to create VMs in project 'demo'?"                │
│  "Yes, here's a TOKEN proving they're authenticated"                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  NOVA-API (Compute API) - Port 8774                                         │
│  "OK, user wants a VM. Let me coordinate with everyone..."                  │
└─────────────────────────────────────────────────────────────────────────────┘
              │                       │                       │
              ▼                       ▼                       ▼
┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────────────┐
│  PLACEMENT - 8778    │ │  GLANCE - 9292       │ │  NEUTRON - 9696          │
│  "Which hypervisor   │ │  "Get me the Ubuntu  │ │  "Create a port on       │
│   has 2GB RAM free?" │ │   image from Ceph"   │ │   'my-network' for this  │
│  "hypervisor-4 does!"│ │                      │ │   VM's network interface"│
└──────────────────────┘ └──────────────────────┘ └──────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  NOVA-SCHEDULER                                                              │
│  "Based on Placement data, hypervisor-4 is the best fit. Sending there..."  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  NOVA-COMPUTE (on hypervisor-4)                                              │
│  "Creating VM via libvirt..."                                                │
│  "Connecting to Ceph to clone the Ubuntu image..."                           │
│  "Attaching network port from OVN..."                                        │
│  "VM is ACTIVE!"                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
                            ┌─────────────────┐
                            │      CEPH       │
                            │  (RBD Storage)  │
                            │                 │
                            │ images pool:    │
                            │  └─ ubuntu.raw  │
                            │ vms pool:       │
                            │  └─ vm-disk-xxx │
                            └─────────────────┘
```

---

## What is Kolla-Ansible?

### The Problem with Traditional OpenStack Installation

Installing OpenStack traditionally requires:
- Installing dozens of packages on each server
- Configuring hundreds of configuration files by hand
- Managing Python dependencies (which often conflict with each other)
- Dealing with version mismatches between services
- Complex upgrades that can break things
- Hours of debugging obscure dependency errors

### The Solution: Kolla-Ansible

**Kolla** = Containerized OpenStack (each service runs in its own Docker container)
**Ansible** = Automation tool that deploys and configures everything

```
Traditional Installation:              Kolla Containers:
┌────────────────────────┐           ┌────────────────────────┐
│       Host OS          │           │       Host OS          │
│ ┌────────────────────┐ │           │ ┌──────┐ ┌──────┐      │
│ │ OpenStack Packages │ │           │ │Glance│ │ Nova │      │
│ │ Python 3.8, 3.10...│ │    vs     │ │(own  │ │(own  │      │
│ │ Library conflicts! │ │           │ │Python│ │Python│      │
│ │ Upgrade nightmare  │ │           │ │ env) │ │ env) │      │
│ └────────────────────┘ │           │ └──────┘ └──────┘      │
└────────────────────────┘           │ ┌──────┐ ┌──────┐      │
                                     │ │Cinder│ │Neutron      │
                                     │ │(own  │ │(own  │      │
                                     │ │ env) │ │ env) │      │
                                     │ └──────┘ └──────┘      │
                                     └────────────────────────┘
                                     Each container is isolated!
```

### Benefits of Kolla-Ansible

| Benefit | Explanation |
|---------|-------------|
| **Isolation** | Each service runs in its own container with its own dependencies - no conflicts |
| **Reproducibility** | Same container images work on any Linux host |
| **Easy Upgrades** | Pull new container images, restart services - done |
| **Rollback** | Keep old images, switch back if something breaks |
| **Consistency** | One tool (kolla-ansible) to deploy, configure, upgrade, and manage |
| **Speed** | Deployment is automated - no manual configuration |

### How Kolla-Ansible Works

```
Your Machine (Hetzner)                   Target Servers (hypervisors)
┌─────────────────────┐                  ┌─────────────────────────────┐
│                     │                  │                             │
│  kolla-ansible      │   SSH + Ansible  │   Docker containers:        │
│  (Python tool)      │ ═══════════════> │   ┌───────────────────────┐ │
│                     │                  │   │ glance_api            │ │
│  Configuration:     │                  │   │ nova_compute          │ │
│  - globals.yml      │                  │   │ cinder_volume         │ │
│  - multinode        │                  │   │ neutron_server        │ │
│  - passwords.yml    │                  │   │ keystone              │ │
│                     │                  │   │ mariadb               │ │
└─────────────────────┘                  │   │ rabbitmq              │ │
                                         │   │ ...and 30+ more       │ │
                                         │   └───────────────────────┘ │
                                         └─────────────────────────────┘
```

---

## What is Ceph and Why Use It?

### Ceph Overview

**Ceph** is a distributed storage system that provides:
- **Object Storage** (like AWS S3) - via RadosGW
- **Block Storage** (like AWS EBS) - via RBD (RADOS Block Device)
- **File Storage** (like NFS) - via CephFS

You've already deployed Ceph! Now we're configuring OpenStack to USE that Ceph cluster.

### Why Ceph for OpenStack? (Critical Benefits)

| Feature | What It Means | Why It Matters |
|---------|---------------|----------------|
| **No single point of failure** | Data is replicated across multiple servers | If a disk or server dies, your VMs keep running |
| **Thin provisioning** | Create 100GB volume, only uses actual data size | Save disk space - you don't need 100GB of actual storage |
| **Copy-on-write clones** | Creating a VM from an image is INSTANT | Doesn't copy the whole image - just references it |
| **Snapshots** | Point-in-time copies with minimal space | Backup VMs instantly |
| **Live migration** | Move running VMs between servers | Maintenance without downtime - VM moves to another host seamlessly |
| **Boot from volume** | VM root disk is a Ceph volume | VM survives compute host failure |
| **Unified storage** | One system for everything | Simpler to manage than separate storage for images/volumes/VMs |

### How OpenStack Uses Ceph

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           YOUR CEPH CLUSTER                                  │
│                                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   images    │  │   volumes   │  │     vms     │  │   backups   │        │
│  │    pool     │  │    pool     │  │    pool     │  │    pool     │        │
│  │             │  │             │  │             │  │             │        │
│  │ Used by:    │  │ Used by:    │  │ Used by:    │  │ Used by:    │        │
│  │ GLANCE      │  │ CINDER      │  │ NOVA        │  │ CINDER-     │        │
│  │             │  │             │  │             │  │ BACKUP      │        │
│  │ Stores:     │  │ Stores:     │  │ Stores:     │  │ Stores:     │        │
│  │ - Ubuntu    │  │ - User      │  │ - VM root   │  │ - Volume    │        │
│  │ - CentOS    │  │   created   │  │   disks     │  │   snapshots │        │
│  │ - Windows   │  │   volumes   │  │ (ephemeral) │  │             │        │
│  │   images    │  │             │  │             │  │             │        │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘        │
│         │                │                │                │                │
│         ▼                ▼                ▼                ▼                │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    RADOS (Ceph's distributed object store)           │   │
│  │                    Data replicated across OSDs on hyp-4 and hyp-5    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Ceph Users for OpenStack

Each OpenStack service gets its own Ceph user with specific permissions:

| Ceph User | Used By | Permissions | Why These Permissions? |
|-----------|---------|-------------|------------------------|
| `client.glance` | Glance (Image service) | Read/Write on `images` pool | Needs to store and serve OS images |
| `client.cinder` | Cinder (Volume service) | Read/Write on `volumes`, `vms`; Read-only on `images` | Creates volumes, can clone from images |
| `client.cinder-backup` | Cinder Backup | Read/Write on `backups` | Stores volume backups |
| `client.nova` | Nova (Compute) | Read/Write on `vms`, `volumes`; Read-only on `images` | Creates VM disks, live migration needs volume access |

---

# PART 2: Your Infrastructure Architecture

## Physical Layout

```
                              INTERNET
                                  │
                     ┌────────────┴────────────┐
                     │     Hetzner Server      │
                     │   (Deployment Host)     │
                     │   - Runs kolla-ansible  │
                     │   - SSH to all hosts    │
                     │   - Stores configs      │
                     └────────────┬────────────┘
                                  │
                     ┌────────────┴────────────┐
                     │     192.168.10.0/24     │
                     │    Management Network    │
                     └────────────┬────────────┘
                                  │
   ┌──────────────────────────────┼──────────────────────────────┐
   │                              │                              │
   │    CONTROL PLANE             │         DATA PLANE           │
   │    (Controllers)             │         (Computes)           │
   │                              │                              │
   │  ┌─────────┐ ┌─────────┐ ┌─────────┐   ┌─────────┐ ┌─────────┐
   │  │  HV-1   │ │  HV-2   │ │  HV-3   │   │  HV-4   │ │  HV-5   │
   │  │.10.11   │ │.10.12   │ │.10.13   │   │.10.14   │ │.10.15   │
   │  ├─────────┤ ├─────────┤ ├─────────┤   ├─────────┤ ├─────────┤
   │  │OpenStack│ │OpenStack│ │OpenStack│   │Nova     │ │Nova     │
   │  │ Control │ │ Control │ │ Control │   │Compute  │ │Compute  │
   │  │Services:│ │Services:│ │Services:│   │(runs VMs│ │(runs VMs│
   │  │-Keystone│ │-Keystone│ │-Keystone│   │         │ │         │
   │  │-Glance  │ │-Glance  │ │-Glance  │   │Cinder   │ │Cinder   │
   │  │-Nova API│ │-Nova API│ │-Nova API│   │Volume   │ │Volume   │
   │  │-Neutron │ │-Neutron │ │-Neutron │   │(serves  │ │(serves  │
   │  │-Horizon │ │-Horizon │ │-Horizon │   │ RBD)    │ │ RBD)    │
   │  │-MariaDB │ │-MariaDB │ │-MariaDB │   │         │ │         │
   │  │-RabbitMQ│ │-RabbitMQ│ │-RabbitMQ│   │OVN      │ │OVN      │
   │  │-OVN DB  │ │-OVN DB  │ │-OVN DB  │   │Controler│ │Controler│
   │  ├─────────┤ ├─────────┤ ├─────────┤   ├─────────┤ ├─────────┤
   │  │Ceph MON │ │Ceph MON │ │Ceph MON │   │Ceph OSD │ │Ceph OSD │
   │  │Ceph MGR │ │Ceph MGR │ │Ceph MGR │   │RadosGW  │ │RadosGW  │
   │  └─────────┘ └─────────┘ └─────────┘   └─────────┘ └─────────┘
   │                              │                              │
   │  ┌───────────────────────────┴───────────────────────────┐  │
   │  │        Anycast VIP: 10.100.0.254 on ALL 3 controllers │  │
   │  │        (Each controller has this IP on lo1 interface) │  │
   │  └───────────────────────────────────────────────────────┘  │
   │                                                             │
   └─────────────────────────────────────────────────────────────┘
```

## Network Design

### IP Addresses Used

| Interface/Purpose | IP Address | Used By |
|-------------------|------------|---------|
| Management (SSH) | 192.168.10.11-15 | All hypervisors - how you reach them |
| API Services | 10.1.0.1-5 | OpenStack APIs bind here (per host) |
| Tunnel (Geneve) | 10.1.0.1-5 | VM-to-VM traffic overlay |
| VIP (Anycast) | 10.100.0.254 | Single endpoint for all API access |

### Why Anycast VIP Instead of Keepalived?

**Traditional HA with Keepalived:**
```
                  VIP: 10.100.0.254
                          │
                          ▼
                 ┌────────────────┐
                 │  Controller 1  │ ◄── VIP lives here (ACTIVE)
                 │  (MASTER)      │
                 └────────────────┘
                 ┌────────────────┐
                 │  Controller 2  │ ◄── No VIP (BACKUP)
                 │  (BACKUP)      │
                 └────────────────┘
                 ┌────────────────┐
                 │  Controller 3  │ ◄── No VIP (BACKUP)
                 │  (BACKUP)      │
                 └────────────────┘

Problem: If Controller 1 fails:
         - Keepalived detects failure (2-5 seconds)
         - VIP moves to Controller 2
         - All existing connections RESET
         - Single point of traffic (no load balancing)
```

**Your Setup (BGP Anycast):**
```
                  VIP: 10.100.0.254
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ Controller 1 │  │ Controller 2 │  │ Controller 3 │
│ lo1: 10.100. │  │ lo1: 10.100. │  │ lo1: 10.100. │
│     0.254/32 │  │     0.254/32 │  │     0.254/32 │
└──────────────┘  └──────────────┘  └──────────────┘
        │                 │                 │
        └────────┬────────┴────────┬───────┘
                 │   BGP announces │
                 ▼   10.100.0.254  ▼
         ┌───────────────────────────────┐
         │      Your Spine Routers       │
         │   Route traffic to NEAREST    │
         │   controller advertising VIP  │
         └───────────────────────────────┘

Benefits:
- ALL 3 controllers have the VIP simultaneously
- Traffic goes to nearest/available controller
- If one fails, BGP reconverges in milliseconds
- Load distributed automatically
- No single point of failure for the VIP
```

**This is why we add the VIP to lo1 on all controllers:**
```bash
# This command (run on each controller) enables anycast
sudo ip addr add 10.100.0.254/32 dev lo1
```

---

# PART 3: Understanding the Configuration Files

## What is globals.yml?

### Purpose

`globals.yml` is the **main configuration file for Kolla-Ansible**. It tells Kolla-Ansible:
- What OpenStack release to deploy
- What Linux distribution to use for containers
- How networking should be configured
- Which services to enable/disable
- How to connect to external systems (like your Ceph cluster)

Think of it as the "master settings file" that controls your entire OpenStack deployment.

### Location

- **Source:** `usvf/kolla-ansible/globals.yml` (in your repo)
- **Destination:** `/etc/kolla/globals.yml` (on deployment host)

### Why It's Important

Every setting in this file affects how your OpenStack cluster behaves:
- Wrong VIP address? APIs unreachable.
- Wrong network interface? Services can't communicate.
- Wrong Ceph settings? Storage doesn't work.

---

## globals.yml Complete Breakdown

Let me explain **every single line** in your globals.yml:

### Section 1: Base Setup

```yaml
# ========================
# 1. Base Setup
# ========================
kolla_base_distro: "ubuntu"
kolla_install_type: "source"
openstack_release: "2024.1"
```

| Setting | Value | What It Does | Why This Value |
|---------|-------|--------------|----------------|
| `kolla_base_distro` | `"ubuntu"` | Base Linux distribution for all Docker containers | Ubuntu has better package availability and is well-tested with OpenStack |
| `kolla_install_type` | `"source"` | How OpenStack is installed inside containers | `source` = from git, `binary` = from packages. Source is more flexible |
| `openstack_release` | `"2024.1"` | OpenStack version codename | 2024.1 is "Caracal" - the latest stable release |

### Section 2: Networking (Underlay)

```yaml
# ========================
# 2. Networking (Underlay)
# ========================
# VIP on Controller Loopbacks (Anycast)
kolla_internal_vip_address: "10.100.0.254"
enable_keepalived: "no"

# Bind services to Host Loopbacks
api_interface_address: "{{ api_ip }}"
tunnel_interface_address: "{{ tunnel_ip }}"

# PURE BGP EXTERNAL (No Physical Bridge)
neutron_external_interface: "dum-ex"
network_interface: "lo1"
```

| Setting | Value | What It Does | Why This Value |
|---------|-------|--------------|----------------|
| `kolla_internal_vip_address` | `"10.100.0.254"` | The Virtual IP address that ALL OpenStack APIs will be accessible at | This is the single entry point for your cloud. Users connect to this IP to access Horizon, APIs, etc. |
| `enable_keepalived` | `"no"` | Disable Keepalived (the default HA mechanism) | You're using BGP Anycast instead - each controller advertises this VIP via BGP, so Keepalived is not needed |
| `api_interface_address` | `"{{ api_ip }}"` | IP address where OpenStack services bind their APIs | Uses a variable from the multinode inventory file - each host has its own api_ip (10.1.0.1, 10.1.0.2, etc.) |
| `tunnel_interface_address` | `"{{ tunnel_ip }}"` | IP address for Geneve/VXLAN tunnel endpoints | VM-to-VM traffic uses overlay tunnels; this is where tunnel traffic enters/exits |
| `neutron_external_interface` | `"dum-ex"` | Network interface for external/provider networks | `dum-ex` is a dummy interface - you're using pure BGP for external connectivity, not a physical bridge |
| `network_interface` | `"lo1"` | Primary interface for inter-service communication | `lo1` is a loopback interface with your service IPs - services communicate via these IPs |

**CRITICAL UNDERSTANDING:** The `{{ api_ip }}` and `{{ tunnel_ip }}` are **Jinja2 variables** that get their values from the multinode inventory file. Each host has different values.

### Section 3: OVN Configuration

```yaml
# ========================
# 3. OVN Configuration
# ========================
neutron_plugin_agent: "ovn"
neutron_tunnel_type: "geneve"
enable_neutron_dvr: "yes"
enable_neutron_provider_networks: "yes"
neutron_ovn_distributed_fip: "yes"
```

| Setting | Value | What It Does | Why This Value |
|---------|-------|--------------|----------------|
| `neutron_plugin_agent` | `"ovn"` | Which networking backend to use | OVN (Open Virtual Network) is the modern replacement for the older OVS+agents. Better performance, simpler architecture |
| `neutron_tunnel_type` | `"geneve"` | Encapsulation protocol for overlay networks | Geneve is the modern replacement for VXLAN - more extensible, better metadata support |
| `enable_neutron_dvr` | `"yes"` | Enable Distributed Virtual Routing | With DVR, each compute node can route traffic locally instead of sending it to a central router. Lower latency! |
| `enable_neutron_provider_networks` | `"yes"` | Allow creating networks that map to physical networks | Needed for VMs that need direct external access (not through NAT) |
| `neutron_ovn_distributed_fip` | `"yes"` | Floating IPs handled on compute nodes | With this, floating IP traffic doesn't need to go through network nodes - direct from compute to external |

### Section 4: OVN BGP Agent

```yaml
# ========================
# 4. OVN BGP AGENT
# ========================
enable_neutron_bgp_dragent: "no"
enable_ovn_bgp_agent: "yes"
ovn_bgp_agent_driver: "nb_ovn_bgp_driver"
```

| Setting | Value | What It Does | Why This Value |
|---------|-------|--------------|----------------|
| `enable_neutron_bgp_dragent` | `"no"` | Disable the old Neutron BGP dynamic routing agent | You're using the newer OVN BGP agent instead |
| `enable_ovn_bgp_agent` | `"yes"` | Enable OVN BGP Agent | This agent advertises tenant network routes via BGP to your fabric |
| `ovn_bgp_agent_driver` | `"nb_ovn_bgp_driver"` | Which OVN BGP driver to use | The NB (Northbound) driver watches OVN Northbound DB and syncs routes to the kernel routing table. FRR (running on the host) then advertises these via BGP |

### Section 5: FRR Handling

```yaml
# -----------------------------------------------------------------
# 5. FRR Handling
# -----------------------------------------------------------------
enable_frr: "no"
```

| Setting | Value | What It Does | Why This Value |
|---------|-------|--------------|----------------|
| `enable_frr` | `"no"` | Don't deploy FRR (Free Range Routing) via Kolla | You already have FRR running on the hosts (from your EVPN/BGP setup). Kolla's FRR would conflict with it |

### Section 6: Core Services

```yaml
# ========================
# 6. Core Services
# ========================
enable_horizon: "yes"
enable_heat: "yes"
enable_fluentd: "yes"
enable_cinder: "yes"
```

| Setting | Value | What It Does | Why This Value |
|---------|-------|--------------|----------------|
| `enable_horizon` | `"yes"` | Deploy the Horizon web dashboard | So you can manage OpenStack via a web browser |
| `enable_heat` | `"yes"` | Deploy Heat (orchestration) | Enables Infrastructure-as-Code - deploy complex stacks from templates |
| `enable_fluentd` | `"yes"` | Deploy Fluentd for log collection | Centralized logging - all container logs collected in one place |
| `enable_cinder` | `"yes"` | Deploy Cinder (block storage) | Enables persistent volumes for VMs - stored in your Ceph cluster |

### Section 7: Ceph Configuration (CRITICAL!)

This is the section that connects OpenStack to your Ceph cluster:

```yaml
# ========================
# 7. Ceph Configuration (External Cluster)
# ========================
# Glance - Store images in Ceph
glance_backend_ceph: "yes"
glance_backend_file: "no"
ceph_glance_keyring: "ceph.client.glance.keyring"
ceph_glance_user: "glance"
ceph_glance_pool_name: "images"
```

| Setting | Value | What It Does | Why This Value |
|---------|-------|--------------|----------------|
| `glance_backend_ceph` | `"yes"` | Store Glance images in Ceph RBD | Instead of storing images on local disk, store them in your distributed Ceph cluster |
| `glance_backend_file` | `"no"` | Disable local file storage for Glance | Can't use both - we want Ceph |
| `ceph_glance_keyring` | `"ceph.client.glance.keyring"` | Filename of the Ceph keyring for Glance | This file contains the authentication key for the `client.glance` Ceph user |
| `ceph_glance_user` | `"glance"` | Ceph username for Glance | Matches the user created with `ceph auth get-or-create client.glance` |
| `ceph_glance_pool_name` | `"images"` | Ceph pool where Glance stores images | Must match the pool name you created in Ceph |

```yaml
# Cinder - Block storage with Ceph RBD
enable_cinder_backend_lvm: "no"
cinder_backend_ceph: "yes"
ceph_cinder_keyring: "ceph.client.cinder.keyring"
ceph_cinder_user: "cinder"
ceph_cinder_pool_name: "volumes"
```

| Setting | Value | What It Does | Why This Value |
|---------|-------|--------------|----------------|
| `enable_cinder_backend_lvm` | `"no"` | Disable LVM backend for Cinder | LVM stores volumes on local disks - we want Ceph instead |
| `cinder_backend_ceph` | `"yes"` | Enable Ceph RBD backend for Cinder | Volumes stored in Ceph = distributed, replicated, thin-provisioned |
| `ceph_cinder_keyring` | `"ceph.client.cinder.keyring"` | Keyring filename for Cinder | Authentication for `client.cinder` Ceph user |
| `ceph_cinder_user` | `"cinder"` | Ceph username for Cinder | Must match user created in Ceph |
| `ceph_cinder_pool_name` | `"volumes"` | Pool for Cinder volumes | Where user-created volumes live |

```yaml
# Cinder Backup to Ceph
cinder_backup_driver: "ceph"
ceph_cinder_backup_keyring: "ceph.client.cinder-backup.keyring"
ceph_cinder_backup_user: "cinder-backup"
ceph_cinder_backup_pool_name: "backups"
```

| Setting | Value | What It Does | Why This Value |
|---------|-------|--------------|----------------|
| `cinder_backup_driver` | `"ceph"` | Use Ceph for volume backups | Backups also go to Ceph - no separate backup storage needed |
| `ceph_cinder_backup_keyring` | `"ceph.client.cinder-backup.keyring"` | Keyring for backup operations | Separate user with access only to backups pool |
| `ceph_cinder_backup_user` | `"cinder-backup"` | Ceph username for backups | Least-privilege: this user can only write to backups pool |
| `ceph_cinder_backup_pool_name` | `"backups"` | Pool for volume backups | Separate pool for backups (different access patterns) |

```yaml
# Nova - Ephemeral disks and live migration with Ceph
nova_backend_ceph: "yes"
ceph_nova_keyring: "ceph.client.nova.keyring"
ceph_nova_user: "nova"
ceph_nova_pool_name: "vms"
```

| Setting | Value | What It Does | Why This Value |
|---------|-------|--------------|----------------|
| `nova_backend_ceph` | `"yes"` | Store VM ephemeral disks in Ceph | VM root disks stored in Ceph = enables live migration, VM survives host failure |
| `ceph_nova_keyring` | `"ceph.client.nova.keyring"` | Keyring for Nova | Authentication for `client.nova` Ceph user |
| `ceph_nova_user` | `"nova"` | Ceph username for Nova | Must match user created in Ceph |
| `ceph_nova_pool_name` | `"vms"` | Pool for VM ephemeral disks | Separate from volumes - different lifecycle (deleted when VM deleted) |

---

## What is the multinode Inventory File?

### Purpose

The `multinode` file is an **Ansible inventory file**. It tells Kolla-Ansible:
- What servers exist in your infrastructure
- What role each server plays (controller, compute, storage, etc.)
- Connection details for each server (IP address, SSH user)
- Host-specific variables (like the api_ip and tunnel_ip used in globals.yml)

Think of it as the "address book" that tells Ansible where to deploy what.

### Location

- **Source:** `usvf/kolla-ansible/multinode` (in your repo)
- **Destination:** `/etc/kolla/multinode` (on deployment host)

### Why It's Important

- Wrong IP address? Ansible can't connect to deploy.
- Wrong group membership? Services deploy to wrong hosts.
- Missing host variables? Services bind to wrong interfaces.

---

## multinode File Complete Explanation

### Primary Groups (The Important Ones)

```ini
[control]
# These hostname must be resolvable from your deployment host
control01 ansible_host=192.168.10.11 ansible_user=ubuntu ansible_become=true api_ip=10.1.0.1 tunnel_ip=10.1.0.1
control02 ansible_host=192.168.10.12 ansible_user=ubuntu ansible_become=true api_ip=10.1.0.2 tunnel_ip=10.1.0.2
control03 ansible_host=192.168.10.13 ansible_user=ubuntu ansible_become=true api_ip=10.1.0.3 tunnel_ip=10.1.0.3
```

**Breaking down each part:**

| Part | Example | What It Means |
|------|---------|---------------|
| `control01` | Hostname | A name for this host (used in Ansible output) |
| `ansible_host=192.168.10.11` | Connection IP | Where Ansible SSHes to reach this host |
| `ansible_user=ubuntu` | SSH user | Connect as ubuntu user (not root) |
| `ansible_become=true` | Use sudo | Elevate privileges for operations requiring root |
| `api_ip=10.1.0.1` | Host variable | Used by `{{ api_ip }}` in globals.yml - where APIs bind |
| `tunnel_ip=10.1.0.1` | Host variable | Used by `{{ tunnel_ip }}` - where tunnel traffic goes |

**The [control] group:** Hosts that run OpenStack control plane services:
- Keystone, Glance, Nova API, Neutron Server, Cinder API
- MariaDB, RabbitMQ, HAProxy
- OVN databases
- Horizon dashboard

```ini
[network]
control01
control02
control03
```

**The [network] group:** Hosts that run Neutron network agents. In your setup, controllers also handle networking (this is common).

```ini
[compute]
compute01 ansible_host=192.168.10.14 ansible_user=ubuntu ansible_become=true api_ip=10.1.0.4 tunnel_ip=10.1.0.4
compute02 ansible_host=192.168.10.15 ansible_user=ubuntu ansible_become=true api_ip=10.1.0.5 tunnel_ip=10.1.0.5
```

**The [compute] group:** Hosts that run VMs. These run:
- Nova compute (libvirt/KVM)
- OVN controller (for networking)
- Neutron metadata agent

```ini
[storage]
compute01
compute02
```

**The [storage] group:** Hosts that run Cinder Volume service. Why compute nodes?
- They have access to Ceph (OSDs are here)
- Volume service needs Ceph client

```ini
[monitoring]
control01
```

**The [monitoring] group:** Where monitoring services run (Prometheus exporters, etc.). Running on one controller is fine for small deployments.

```ini
[deployment]
localhost       ansible_connection=local
```

**The [deployment] group:** The machine running kolla-ansible. Uses local connection (not SSH).

### Service-to-Host Mapping Groups

The rest of the file maps specific OpenStack services to hosts. Example:

```ini
[glance:children]
control

[glance-api:children]
glance
```

This means:
- `glance` group inherits from `control` group (all controllers)
- `glance-api` runs wherever `glance` runs

```ini
[cinder-volume:children]
storage
```

This means `cinder-volume` runs on hosts in `[storage]` group (your compute nodes).

### Understanding :children

When you see:
```ini
[some-group:children]
other-group
```

It means "some-group" includes all hosts from "other-group". It's Ansible's way of creating group hierarchies.

### Your OVN-Specific Groups

```ini
[ovn-controller:children]
ovn-controller-compute
ovn-controller-network

[ovn-controller-compute:children]
compute

[ovn-controller-network:children]
network

[ovn-database:children]
control
```

This means:
- OVN Controller runs on both compute and network nodes
- OVN Database runs on controllers (needs quorum, so 3 nodes)

```ini
[ovn-bgp-agent:children]
control
compute
```

OVN BGP Agent runs on ALL nodes - both controllers and computes. This is what advertises routes to your FRR.

---

# PHASE 1: Ceph Preparation for OpenStack

## Goal

Create dedicated Ceph users with specific permissions for each OpenStack service.

## Prerequisites

- Ceph cluster is healthy (`ceph -s` shows HEALTH_OK)
- Pools already exist: `volumes`, `images`, `backups`, `vms`
- You can SSH to hypervisor-1 (a Ceph MON node)

## Step 1: SSH to Ceph Admin Node

```bash
# From your Hetzner server
ssh ubuntu@192.168.10.11
```

## Step 2: Enter Ceph Admin Shell

```bash
# On hypervisor-1
sudo cephadm shell
```

**What this does:** Opens a shell inside the Ceph admin container where you can run `ceph` commands.

## Step 3: Verify Ceph Health and Pools

```bash
# Check cluster health
ceph -s

# List existing pools
ceph osd pool ls
# Expected output: volumes, images, backups, vms (plus any others)
```

## Step 4: Create Ceph Users for OpenStack

### User 1: client.glance (for Image service)

```bash
ceph auth get-or-create client.glance \
    mon 'profile rbd' \
    osd 'profile rbd pool=images' \
    mgr 'profile rbd pool=images'
```

**Explanation:**
- `get-or-create` - Create user if doesn't exist, or return existing
- `client.glance` - Username (OpenStack Glance will use this)
- `mon 'profile rbd'` - Allow basic MON operations needed for RBD
- `osd 'profile rbd pool=images'` - Read/write access to `images` pool only
- `mgr 'profile rbd pool=images'` - MGR permissions for `images` pool

### User 2: client.cinder (for Volume service)

```bash
ceph auth get-or-create client.cinder \
    mon 'profile rbd' \
    osd 'profile rbd pool=volumes, profile rbd pool=vms, profile rbd-read-only pool=images' \
    mgr 'profile rbd pool=volumes, profile rbd pool=vms'
```

**Explanation:**
- Read/write on `volumes` pool (create/delete volumes)
- Read/write on `vms` pool (needed for some operations)
- **Read-only** on `images` pool (to clone images into volumes)

### User 3: client.cinder-backup (for Volume Backup service)

```bash
ceph auth get-or-create client.cinder-backup \
    mon 'profile rbd' \
    osd 'profile rbd pool=backups' \
    mgr 'profile rbd pool=backups'
```

**Explanation:**
- Only needs access to `backups` pool
- Least privilege - can't touch volumes or images

### User 4: client.nova (for Compute service)

```bash
ceph auth get-or-create client.nova \
    mon 'profile rbd' \
    osd 'profile rbd pool=vms, profile rbd pool=volumes, profile rbd-read-only pool=images' \
    mgr 'profile rbd pool=vms'
```

**Explanation:**
- Read/write on `vms` pool (VM ephemeral disks)
- Read/write on `volumes` pool (for live migration!)
- Read-only on `images` (to clone images for VM disks)

## Step 5: Export Keyrings to Files

```bash
# Export each user's keyring
ceph auth get client.glance -o /etc/ceph/ceph.client.glance.keyring
ceph auth get client.cinder -o /etc/ceph/ceph.client.cinder.keyring
ceph auth get client.cinder-backup -o /etc/ceph/ceph.client.cinder-backup.keyring
ceph auth get client.nova -o /etc/ceph/ceph.client.nova.keyring

# Set readable permissions (needed for copying later)
chmod 644 /etc/ceph/ceph.client.*.keyring

# Verify files were created
ls -la /etc/ceph/ceph.client.*.keyring
```

## Step 6: Verify Users Were Created

```bash
# List all users
ceph auth ls | grep -E "client\.(glance|cinder|nova)"
```

Expected output:
```
client.cinder
client.cinder-backup
client.glance
client.nova
```

## Step 7: Exit Ceph Shell

```bash
exit
```

Then exit SSH:
```bash
exit
```

---

# PHASE 2: Deployment Host Setup

## Goal

Install Kolla-Ansible and its dependencies on your Hetzner server.

## Step 1: Install System Dependencies

```bash
# On Hetzner server
sudo apt update
sudo apt install -y python3-dev libffi-dev gcc libssl-dev python3-venv git
```

**What each package does:**
| Package | Purpose |
|---------|---------|
| `python3-dev` | Python header files for compiling Python extensions |
| `libffi-dev` | Foreign Function Interface library - needed by cryptography package |
| `gcc` | C compiler - needed to build Python packages with C extensions |
| `libssl-dev` | OpenSSL development files - for TLS/SSL support |
| `python3-venv` | Python virtual environment support |
| `git` | Version control - for downloading kolla-ansible source |

## Step 2: Create Python Virtual Environment

```bash
# Create virtual environment
python3 -m venv ~/kolla-venv

# Activate it
source ~/kolla-venv/bin/activate
```

**Why a virtual environment?**
- Isolates Kolla-Ansible's Python dependencies from system Python
- Prevents conflicts with other Python tools
- Easy to remove/recreate if needed

**You'll see your prompt change to:**
```
(kolla-venv) user@hetzner:~$
```

## Step 3: Install Kolla-Ansible

```bash
# Upgrade pip first
pip install -U pip

# Install Ansible (Kolla-Ansible needs Ansible 8.x or 9.x)
pip install "ansible>=8,<10"

# Install Kolla-Ansible for OpenStack 2024.1 (Caracal)
pip install "kolla-ansible==18.0.0"

# Install Ansible Galaxy dependencies
kolla-ansible install-deps
```

**Version mapping:**
| OpenStack Release | Kolla-Ansible Version |
|-------------------|----------------------|
| 2024.1 (Caracal) | 18.x.x |
| 2023.2 (Bobcat) | 17.x.x |
| 2023.1 (Antelope) | 16.x.x |

## Step 4: Create Kolla Configuration Directory

```bash
# Create the directory
sudo mkdir -p /etc/kolla

# Make it writable by your user
sudo chown $USER:$USER /etc/kolla

# Copy example configuration files
cp -r ~/kolla-venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
```

**What gets copied:**
- `globals.yml` - Main configuration (you'll replace this)
- `passwords.yml` - Empty, will be populated by kolla-genpwd
- `multinode` - Example inventory (you'll replace this)

## Step 5: Generate Passwords

```bash
kolla-genpwd
```

**What this does:**
- Generates random passwords for all OpenStack services
- Populates `/etc/kolla/passwords.yml`
- Includes: database passwords, RabbitMQ passwords, Keystone admin password, etc.

**IMPORTANT:** Save `/etc/kolla/passwords.yml` securely! Your admin password for Horizon is in there.

To see your Horizon admin password:
```bash
grep keystone_admin_password /etc/kolla/passwords.yml
```

---

# PHASE 3: Copy Configuration Files

## Goal

Copy your customized globals.yml and multinode files to /etc/kolla/.

## Step 1: Copy Configuration Files

```bash
# Assuming you have the usvf repo cloned on Hetzner
# Navigate to where your repo is (adjust path as needed)
cd ~/usvf  # or wherever your repo is

# Copy globals.yml
cp usvf/kolla-ansible/globals.yml /etc/kolla/globals.yml

# Copy multinode inventory
cp usvf/kolla-ansible/multinode /etc/kolla/multinode
```

## Step 2: Verify the Files

```bash
# Check globals.yml has Ceph configuration
grep -E "ceph|glance_backend|cinder_backend|nova_backend" /etc/kolla/globals.yml

# Check multinode has your hosts
grep -E "192.168.10" /etc/kolla/multinode
```

---

# PHASE 4: Ceph Config Distribution

## Goal

Copy Ceph configuration and keyrings to the Kolla config directory so Kolla can inject them into containers.

## Understanding the Directory Structure

Kolla-Ansible reads additional configuration from `/etc/kolla/config/`. For each service that needs Ceph access, you need to provide:
1. `ceph.conf` - Tells the service where to find Ceph MONs
2. `ceph.client.<user>.keyring` - Authentication credentials

```
/etc/kolla/config/
├── glance/                          # Glance gets:
│   ├── ceph.conf                    #   - Ceph cluster info
│   └── ceph.client.glance.keyring   #   - Glance credentials
├── cinder/                          # Cinder gets:
│   ├── ceph.conf                    #   - Ceph cluster info
│   ├── cinder-volume/               #   For cinder-volume container:
│   │   └── ceph.client.cinder.keyring    # Cinder credentials
│   └── cinder-backup/               #   For cinder-backup container:
│       └── ceph.client.cinder-backup.keyring  # Backup credentials
└── nova/                            # Nova gets:
    ├── ceph.conf                    #   - Ceph cluster info
    ├── ceph.client.nova.keyring     #   - Nova credentials
    └── ceph.client.cinder.keyring   #   - Cinder credentials (for live migration!)
```

## Step 1: Create Directory Structure

```bash
# On Hetzner (deployment host)
mkdir -p /etc/kolla/config/glance
mkdir -p /etc/kolla/config/cinder/cinder-volume
mkdir -p /etc/kolla/config/cinder/cinder-backup
mkdir -p /etc/kolla/config/nova
```

## Step 2: Copy ceph.conf to Each Service

```bash
# Set variable for convenience
CEPH_ADMIN="ubuntu@192.168.10.11"

# Copy ceph.conf to each service directory
scp $CEPH_ADMIN:/etc/ceph/ceph.conf /etc/kolla/config/glance/
scp $CEPH_ADMIN:/etc/ceph/ceph.conf /etc/kolla/config/cinder/
scp $CEPH_ADMIN:/etc/ceph/ceph.conf /etc/kolla/config/nova/
```

## Step 3: Copy Keyrings

```bash
# Glance keyring
scp $CEPH_ADMIN:/etc/ceph/ceph.client.glance.keyring /etc/kolla/config/glance/

# Cinder Volume keyring
scp $CEPH_ADMIN:/etc/ceph/ceph.client.cinder.keyring /etc/kolla/config/cinder/cinder-volume/

# Cinder Backup keyring
scp $CEPH_ADMIN:/etc/ceph/ceph.client.cinder-backup.keyring /etc/kolla/config/cinder/cinder-backup/

# Nova keyrings (TWO needed!)
scp $CEPH_ADMIN:/etc/ceph/ceph.client.nova.keyring /etc/kolla/config/nova/
scp $CEPH_ADMIN:/etc/ceph/ceph.client.cinder.keyring /etc/kolla/config/nova/
```

**Why does Nova need cinder.keyring?**
Live migration requires Nova to access Cinder volumes. When a VM with attached volumes is migrated, Nova needs to tell the destination compute node about the volume - this requires Cinder credentials.

## Step 4: Verify Everything is in Place

```bash
# List all files
find /etc/kolla/config -type f

# Expected output:
# /etc/kolla/config/glance/ceph.conf
# /etc/kolla/config/glance/ceph.client.glance.keyring
# /etc/kolla/config/cinder/ceph.conf
# /etc/kolla/config/cinder/cinder-volume/ceph.client.cinder.keyring
# /etc/kolla/config/cinder/cinder-backup/ceph.client.cinder-backup.keyring
# /etc/kolla/config/nova/ceph.conf
# /etc/kolla/config/nova/ceph.client.nova.keyring
# /etc/kolla/config/nova/ceph.client.cinder.keyring
```

---

# PHASE 5: Node Preparation

## Goal

Prepare all target nodes (hypervisors) for OpenStack deployment.

## Step 5.1: Add Anycast VIP to Controller Loopbacks

**THIS IS CRITICAL!** Each controller needs the VIP address on its loopback interface so BGP can advertise it.

### What We're Doing and Why

Remember from the architecture section: we're using BGP Anycast instead of Keepalived. This means:
1. Each controller has the VIP (10.100.0.254) on a loopback interface
2. Each controller advertises this IP via BGP
3. Your spine routers send traffic to the nearest controller

### Command to Run

```bash
# From Hetzner, configure VIP on all 3 controllers
for host in 192.168.10.11 192.168.10.12 192.168.10.13; do
    echo "Adding VIP to $host..."
    ssh ubuntu@$host "sudo ip addr add 10.100.0.254/32 dev lo1 2>/dev/null || echo 'Already configured'"
done
```

**Command breakdown:**
| Part | What It Does |
|------|--------------|
| `ip addr add` | Add an IP address |
| `10.100.0.254/32` | The VIP with /32 mask (host route) |
| `dev lo1` | On the lo1 loopback interface |
| `2>/dev/null` | Suppress error if already exists |
| `\|\| echo 'Already configured'` | Show message if already configured |

### Verify VIP is Configured

```bash
# Check each controller
for host in 192.168.10.11 192.168.10.12 192.168.10.13; do
    echo "=== $host ==="
    ssh ubuntu@$host "ip addr show lo1 | grep 10.100.0.254"
done
```

Expected output for each host:
```
    inet 10.100.0.254/32 scope global lo1
```

### Make VIP Persistent (Survives Reboot)

The `ip addr add` command doesn't survive reboots. To make it persistent:

```bash
# Add to netplan on each controller
for host in 192.168.10.11 192.168.10.12 192.168.10.13; do
    echo "Making VIP persistent on $host..."
    ssh ubuntu@$host "grep -q '10.100.0.254' /etc/netplan/*.yaml || echo 'Need to add to netplan manually'"
done
```

**Note:** Depending on your netplan configuration, you may need to add the VIP to your netplan YAML files manually. This is something to discuss based on your current netplan setup.

## Step 5.2: Install Ceph Client on All Nodes

All OpenStack nodes need the Ceph client libraries to connect to your Ceph cluster.

```bash
# Install on ALL nodes (controllers + computes)
for host in 192.168.10.11 192.168.10.12 192.168.10.13 192.168.10.14 192.168.10.15; do
    echo "Installing Ceph client on $host..."
    ssh ubuntu@$host "sudo apt update && sudo apt install -y ceph-common python3-rbd"
done
```

**What gets installed:**
| Package | Purpose |
|---------|---------|
| `ceph-common` | Ceph client tools and libraries (rbd, rados commands) |
| `python3-rbd` | Python bindings for RBD - needed by OpenStack services |

## Step 5.3: Run Kolla Bootstrap

Kolla's bootstrap prepares all nodes for OpenStack deployment.

```bash
# Make sure you're in the virtual environment
source ~/kolla-venv/bin/activate

# Run bootstrap
kolla-ansible -i /etc/kolla/multinode bootstrap-servers
```

**What bootstrap-servers does on each target node:**

| Step | What It Does | Why It's Needed |
|------|--------------|-----------------|
| Install Docker | Installs Docker CE from official repo | Kolla runs all services in containers |
| Configure Docker | Sets storage driver, logging, registry settings | Optimal settings for OpenStack containers |
| Create kolla user | Creates user/group for running containers | Security - containers don't run as root |
| Create directories | Creates /etc/kolla, /var/lib/kolla, etc. | Where configs and data are stored |
| Configure NTP | Ensures time is synchronized | OpenStack services are time-sensitive |
| Set sysctl | Tunes kernel parameters (vm.swappiness, etc.) | Performance optimization |
| Pull kolla-toolbox | Pre-pulls the toolbox container | Used by later deployment steps |

**Expected duration:** 5-15 minutes depending on network speed.

**If it fails:** Read the error carefully. Common issues:
- SSH key not authorized
- sudo requires password
- Network timeout downloading packages

---

# PHASE 6: Pre-deployment Checks

## Goal

Validate that everything is correctly configured before deploying.

## Run Prechecks

```bash
source ~/kolla-venv/bin/activate
kolla-ansible -i /etc/kolla/multinode prechecks
```

## What Prechecks Validates

| Check | What It Verifies |
|-------|------------------|
| Network interfaces | `lo1` and `dum-ex` interfaces exist |
| Docker running | Docker daemon is active on all nodes |
| Ceph config present | ceph.conf and keyrings are in /etc/kolla/config/ |
| Port availability | Required ports (5000, 8774, etc.) are not in use |
| Disk space | Sufficient space in /var/lib/docker |
| Service configs | globals.yml settings are valid |
| Container registry | Can pull container images |

## Common Precheck Failures and Solutions

### "Interface 'lo1' not found"

**Solution:** Create the interface or check your netplan configuration.

### "Ceph keyring not found for glance"

**Solution:** Verify keyring file exists:
```bash
ls -la /etc/kolla/config/glance/
```

### "Port 5000 is already in use"

**Solution:** Find what's using it:
```bash
ssh ubuntu@192.168.10.11 "sudo ss -tlnp | grep 5000"
```

---

# PHASE 7: Deployment

## Goal

Deploy all OpenStack services.

## Run Deployment

```bash
source ~/kolla-venv/bin/activate
kolla-ansible -i /etc/kolla/multinode deploy
```

**Expected duration:** 30-60 minutes (varies based on network speed and server performance).

## Monitor Deployment Progress

In another terminal:
```bash
# Watch containers being created on a controller
ssh ubuntu@192.168.10.11 "watch -n 5 'docker ps --format \"table {{.Names}}\t{{.Status}}\" | head -30'"
```

## Deployment Order

Kolla deploys services in dependency order:

1. **Common services** - fluentd, cron, kolla-toolbox (on all nodes)
2. **HAProxy** - Load balancer for APIs
3. **MariaDB** - Database (with Galera clustering)
4. **RabbitMQ** - Message queue (clustered)
5. **Memcached** - Caching layer
6. **Keystone** - Identity service (needed by everything else)
7. **Glance** - Image service
8. **Cinder** - Block storage service
9. **Placement** - Resource tracking
10. **Nova** - Compute service
11. **Neutron/OVN** - Networking
12. **Heat** - Orchestration
13. **Horizon** - Dashboard

## If Deployment Fails

1. **Read the error message carefully**
2. **Check container logs:**
   ```bash
   ssh ubuntu@192.168.10.11 "docker logs <container-name>"
   ```
3. **Fix the issue**
4. **Resume deployment:**
   ```bash
   kolla-ansible -i /etc/kolla/multinode deploy --limit <failed-host>
   ```

---

# PHASE 8: Post-deployment

## Goal

Complete setup and verify basic functionality.

## Step 1: Run Post-Deploy

```bash
source ~/kolla-venv/bin/activate
kolla-ansible -i /etc/kolla/multinode post-deploy
```

**What this does:**
- Generates `/etc/kolla/admin-openrc.sh` (OpenStack credentials)
- Generates `/etc/kolla/clouds.yaml` (for openstackclient)

## Step 2: Install OpenStack CLI

```bash
pip install python-openstackclient
```

## Step 3: Load Admin Credentials

```bash
source /etc/kolla/admin-openrc.sh
```

## Step 4: Verify Services

```bash
# List all OpenStack services
openstack service list

# Expected output shows: keystone, glance, nova, neutron, cinder, heat, placement

# Check compute services
openstack compute service list

# Should show nova-scheduler, nova-conductor on controllers
# And nova-compute on compute nodes

# Check network agents
openstack network agent list

# Should show OVN agents on all nodes

# Check volume services
openstack volume service list

# Should show cinder-scheduler on controllers
# And cinder-volume on storage nodes (compute01, compute02)
```

## Step 5: Access Horizon Dashboard

1. Open browser to: `http://10.100.0.254`
2. Username: `admin`
3. Password: Get it from passwords.yml:
   ```bash
   grep keystone_admin_password /etc/kolla/passwords.yml
   ```
4. Domain: `Default`

---

# PHASE 9: Verification & Testing

## Test 1: Verify Ceph Connectivity

```bash
# From inside the Cinder volume container
ssh ubuntu@192.168.10.14 "docker exec cinder_volume ceph -s"
```

**Expected:** Ceph cluster status showing HEALTH_OK.

If this fails, check:
- ceph.conf has correct MON addresses
- Keyring file is present and has correct permissions

## Test 2: Create a Volume (Tests Cinder + Ceph)

```bash
source /etc/kolla/admin-openrc.sh

# Create a 1GB volume
openstack volume create --size 1 test-volume

# List volumes
openstack volume list

# Verify in Ceph
ssh ubuntu@192.168.10.14 "docker exec cinder_volume rbd -p volumes ls"
# Should show: volume-<uuid>
```

## Test 3: Upload an Image (Tests Glance + Ceph)

```bash
# Download tiny test image
wget https://download.cirros-cloud.net/0.5.2/cirros-0.5.2-x86_64-disk.img

# Upload to Glance
openstack image create "cirros" \
    --file cirros-0.5.2-x86_64-disk.img \
    --disk-format qcow2 \
    --container-format bare \
    --public

# List images
openstack image list

# Verify in Ceph
ssh ubuntu@192.168.10.11 "docker exec glance_api rbd -p images ls"
# Should show the image ID
```

## Test 4: Create a Network

```bash
# Create internal network
openstack network create test-network

# Create subnet
openstack subnet create test-subnet \
    --network test-network \
    --subnet-range 10.0.0.0/24 \
    --gateway 10.0.0.1 \
    --dns-nameserver 8.8.8.8

# List networks
openstack network list
```

## Test 5: Launch a VM (The Ultimate Test)

```bash
# Create a flavor (VM size)
openstack flavor create --ram 512 --disk 1 --vcpus 1 m1.tiny

# Launch VM
openstack server create \
    --image cirros \
    --flavor m1.tiny \
    --network test-network \
    test-vm

# Watch it boot
watch openstack server list

# Once ACTIVE, get console URL
openstack console url show test-vm
```

## Test 6: Verify VM Disk is in Ceph

```bash
# Check vms pool
ssh ubuntu@192.168.10.14 "docker exec nova_compute rbd -p vms ls"
# Should show: <instance-uuid>_disk
```

---

# Troubleshooting Guide

## Problem: "Failed to connect to Ceph cluster"

**Symptoms:**
- Cinder volume creation fails
- Glance image upload fails
- Error mentions RBD or Ceph connection

**Diagnosis:**
```bash
# Check ceph.conf inside container
ssh ubuntu@192.168.10.14 "docker exec cinder_volume cat /etc/ceph/ceph.conf"

# Check keyring exists
ssh ubuntu@192.168.10.14 "docker exec cinder_volume ls -la /etc/ceph/"

# Test Ceph connection
ssh ubuntu@192.168.10.14 "docker exec cinder_volume ceph -s"
```

**Solutions:**
1. Verify ceph.conf has correct MON addresses
2. Verify keyring filename matches what's in globals.yml
3. Verify Ceph user has correct permissions (`ceph auth get client.cinder`)

## Problem: "Live migration fails"

**Symptoms:**
- VM migration fails with RBD access error
- Error mentions unable to access volume

**Solution:**
Ensure `ceph.client.cinder.keyring` is in `/etc/kolla/config/nova/`:
```bash
ls /etc/kolla/config/nova/ceph.client.cinder.keyring

# If missing, copy it:
scp ubuntu@192.168.10.11:/etc/ceph/ceph.client.cinder.keyring /etc/kolla/config/nova/

# Reconfigure Nova
kolla-ansible -i /etc/kolla/multinode reconfigure --tags nova
```

## Problem: "VIP not reachable"

**Diagnosis:**
```bash
# Check VIP is on controllers
for host in 192.168.10.11 192.168.10.12 192.168.10.13; do
    echo "=== $host ==="
    ssh ubuntu@$host "ip addr show lo1 | grep 10.100.0.254"
done

# Check BGP is advertising it
ssh ubuntu@192.168.10.11 "sudo vtysh -c 'show ip bgp'"
```

**Solution:**
```bash
# Add VIP if missing
ssh ubuntu@192.168.10.11 "sudo ip addr add 10.100.0.254/32 dev lo1"
```

## Problem: Specific Service Not Working

**Reconfigure individual services:**
```bash
# Just Cinder
kolla-ansible -i /etc/kolla/multinode reconfigure --tags cinder

# Just Glance
kolla-ansible -i /etc/kolla/multinode reconfigure --tags glance

# Just Nova
kolla-ansible -i /etc/kolla/multinode reconfigure --tags nova

# Just Neutron/OVN
kolla-ansible -i /etc/kolla/multinode reconfigure --tags neutron
```

## Log Locations

| Service | Container Log | Log Path Inside Container |
|---------|---------------|--------------------------|
| Glance | `docker logs glance_api` | `/var/log/kolla/glance/` |
| Cinder | `docker logs cinder_volume` | `/var/log/kolla/cinder/` |
| Nova | `docker logs nova_compute` | `/var/log/kolla/nova/` |
| Keystone | `docker logs keystone` | `/var/log/kolla/keystone/` |
| Neutron | `docker logs neutron_server` | `/var/log/kolla/neutron/` |
| OVN | `docker logs ovn_controller` | `/var/log/kolla/openvswitch/` |

---

# Quick Reference Checklist

## Pre-Deployment Checklist

- [ ] Ceph cluster is HEALTH_OK
- [ ] Pools exist: `volumes`, `images`, `backups`, `vms`
- [ ] Ceph users created: `client.glance`, `client.cinder`, `client.cinder-backup`, `client.nova`
- [ ] Keyrings exported to /etc/ceph/ on Ceph admin node
- [ ] Kolla-Ansible installed in virtual environment
- [ ] /etc/kolla/globals.yml configured with Ceph settings
- [ ] /etc/kolla/multinode has correct host IPs
- [ ] /etc/kolla/config/ has Ceph configs for glance, cinder, nova
- [ ] VIP 10.100.0.254/32 added to lo1 on all 3 controllers
- [ ] ceph-common installed on all nodes
- [ ] `kolla-ansible bootstrap-servers` completed
- [ ] `kolla-ansible prechecks` passed

## Post-Deployment Checklist

- [ ] `openstack service list` shows all services
- [ ] `openstack compute service list` shows all compute nodes
- [ ] `openstack network agent list` shows OVN agents
- [ ] `openstack volume service list` shows cinder services
- [ ] Can access Horizon at http://10.100.0.254
- [ ] Test volume created and visible in Ceph
- [ ] Test image uploaded and visible in Ceph
- [ ] Test VM created successfully

## File Locations Reference

| File | Location | Purpose |
|------|----------|---------|
| globals.yml | `/etc/kolla/globals.yml` | Main OpenStack config |
| multinode | `/etc/kolla/multinode` | Ansible inventory |
| passwords.yml | `/etc/kolla/passwords.yml` | All service passwords |
| admin-openrc.sh | `/etc/kolla/admin-openrc.sh` | Admin credentials (created post-deploy) |
| Glance ceph.conf | `/etc/kolla/config/glance/ceph.conf` | Ceph config for Glance |
| Glance keyring | `/etc/kolla/config/glance/ceph.client.glance.keyring` | Glance Ceph credentials |
| Cinder ceph.conf | `/etc/kolla/config/cinder/ceph.conf` | Ceph config for Cinder |
| Cinder keyring | `/etc/kolla/config/cinder/cinder-volume/ceph.client.cinder.keyring` | Cinder Ceph credentials |
| Cinder-backup keyring | `/etc/kolla/config/cinder/cinder-backup/ceph.client.cinder-backup.keyring` | Backup Ceph credentials |
| Nova ceph.conf | `/etc/kolla/config/nova/ceph.conf` | Ceph config for Nova |
| Nova keyring | `/etc/kolla/config/nova/ceph.client.nova.keyring` | Nova Ceph credentials |
| Nova cinder keyring | `/etc/kolla/config/nova/ceph.client.cinder.keyring` | For live migration |

---

**Congratulations!** If you've made it through this guide and all tests pass, you have a fully functional OpenStack cloud with Ceph backend storage, OVN networking, and BGP-based high availability.
