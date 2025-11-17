# How To Use This Lab

## Part 1: Infrastructure Setup (One Command)

Run the setup script to prepare everything:

```bash
cd /Users/davidingraham/Desktop/personal_projects/networkAutomation/ContainerLabsProjects/ansible-bgp-containerlab

chmod +x setup.sh
./setup.sh
```

This script does:
1. Builds custom Docker image (if not exists) - has Ansible, Python, gRPC tools
2. Deploys ContainerLab topology (if not running) - creates 3 containers
3. Configures data plane IPs (10.0.1.1 and 10.0.1.2 on eth1 interfaces)
4. Copies configuration files to automation container

When complete, you'll see:
```
Infrastructure Setup Complete!
Lab Status:
  • Management Network: 10.1.1.0/24
  • Automation:  10.1.1.10 (tools ready)
  • FRR1:        10.1.1.11 (SSH enabled)
  • GoBGP1:      10.1.1.12 (gRPC API ready)
  • Data Plane:  frr1:10.0.1.1 <-> gobgp1:10.0.1.2
```

## Part 2: BGP Configuration (Ansible)

Enter the automation container:

```bash
docker exec -it clab-bgp-lab-automation bash
cd /workspace
```

Test connectivity (optional):

```bash
# Test management network
ping -c 2 10.1.1.11  # FRR
ping -c 2 10.1.1.12  # GoBGP

# Test data plane
docker exec clab-bgp-lab-frr1 ping -c 2 10.0.1.2

# Test SSH to FRR
sshpass -p admin123 ssh -o StrictHostKeyChecking=no root@10.1.1.11 "vtysh -c 'show version'"
```

Run the Ansible playbook:

```bash
ansible-playbook -i inventory.yml config_playbook.yml
```

This configures:
1. GoBGP BGP settings via Python gRPC (AS 65002, neighbor to FRR)
2. FRR BGP settings via SSH (AS 65001, neighbor to GoBGP)
3. Verifies BGP sessions established

## Part 3: Verify BGP is Working

From automation container:

```bash
# Check FRR BGP status
sshpass -p admin123 ssh root@10.1.1.11 "vtysh -c 'show bgp summary'"

# Check GoBGP status (if gobgp CLI is available)
# Or use the Python script to query via gRPC
```

## Architecture

```
Automation Container (10.1.1.10)
    |
    | Management Network (10.1.1.0/24)
    |
    +-- FRR1 (10.1.1.11) ←--→ GoBGP1 (10.1.1.12)
           |                      |
           | Data Plane           |
           | (10.0.1.0/30)        |
           +----------------------+
```

## What's Different from Port Forwarding Approach

- No `localhost:50051` mappings
- Each device has predictable management IP
- Ansible runs from container on management network
- Uses SSH for FRR (network_cli)
- Uses gRPC for GoBGP (Python script)
- Scalable: add more routers without port conflicts

