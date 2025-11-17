# BGP Automation Lab

BGP lab using ContainerLab with static management network addressing.

## Why Static Management IPs

**Without static IPs (port forwarding approach):**
- ContainerLab assigns dynamic IPs (172.20.20.x)
- Can't predict which device gets which IP
- Must use port forwarding to localhost (8080:8080, 50051:50051)
- Each additional device needs a different host port
- Doesn't scale beyond a few devices

**With static management IPs:**
- Each device has a known, fixed IP (10.1.1.x)
- Connect directly to device IPs from anywhere on the management network
- All devices can use the same API port (50051)


## Architecture

**Management Network:** 10.1.1.0/24
- frr1: 10.1.1.11 (AS 65001)
- gobgp1: 10.1.1.12 (AS 65002)

**Data Plane:**
- Link between frr1:eth1 and gobgp1:eth1

## What's Included

**Topology (topology.yml):**
- Automation container with Python, Ansible, gRPC tools
- FRR router with SSH enabled
- GoBGP router with gRPC API

**Configuration Tools:**
- `create-links.sh` - Configure data plane interfaces
- `configure_gobgp.py` - Python script using gRPC to configure GoBGP
- `config_playbook.yml` - Ansible playbook orchestrating configuration
- `inventory.yml` - Ansible inventory with router details

**Setup Flow (Infrastructure):**
1. Build custom Docker image with Ansible/Python/gRPC tools
2. Deploy ContainerLab topology (creates containers and management network)
3. Configure data plane interface IPs (eth1 on both routers)
4. Copy configuration files to automation container

**Configuration Flow (BGP Protocol):**
1. Ansible runs from automation container
2. Configures GoBGP via Python gRPC API (AS, router-id, neighbor, routes)
3. Configures FRR via SSH using network_cli (AS, router-id, neighbor, routes)
4. BGP peering established between routers

## Quick Start

See [HOWTO.md](HOWTO.md) for detailed instructions.

```bash
# 1. Setup infrastructure (one command does everything)
chmod +x setup.sh
./setup.sh

# 2. Configure BGP from automation container
docker exec -it clab-bgp-lab-automation bash
cd /workspace
ansible-playbook -i inventory.yml config_playbook.yml
```

The `setup.sh` script handles:
- Building custom Docker image (one-time)
- Deploying ContainerLab topology
- Configuring data plane interfaces
- Copying configuration files

