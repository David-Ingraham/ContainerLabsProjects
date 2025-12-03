# BGP Lab with ContainerLab and Automation

Network automation lab demonstrating BGP configuration between FRR and GoBGP routers using Ansible and gRPC.

## Prerequisites

- Docker installed and running
- Access to containerlab image (ghcr.io/srl-labs/clab)
- Platform support:
  - Linux/macOS: setup.sh
  - Windows: setup.ps1 (PowerShell)

## Credentials Management

This project uses a two-file approach for credentials:

### credentials.env (required, gitignored)

Create this file in the project root on each build machine:

```
FRR_ROOT_PASS=<root-password>
FRR_USER=<ansible-username>
FRR_PASS=<ansible-password>
```

This file is:
- Used at image build time to bake credentials into the FRR Docker image
- Sourced by setup scripts to generate credentials.yml
- Listed in .gitignore (not committed to version control)

### credentials.yml (auto-generated)

The setup scripts generate this file from credentials.env:

```yaml
ansible_user: <value-from-FRR_USER>
ansible_password: <value-from-FRR_PASS>
```

This file is:
- Used by Ansible to authenticate to FRR containers
- Regenerated on each setup script run
- Listed in .gitignore

### Why Two Files?

Shell/Docker consume KEY=VALUE format natively. Ansible's `vars_files` requires YAML. The .env file is the source of truth; credentials.yml is generated from it.

### Cross-Machine Builds

If building on multiple machines (e.g., Mac and Windows), each machine needs its own credentials.env. The credentials can differ between machines as long as:
- The same credentials.env is used for both the Docker image build and Ansible configuration on that machine
- If transferring a pre-built frr-ansible image between machines, the receiving machine's credentials.env must match what was baked into the image

## Network Topology

Management Network: 10.1.1.0/24
- Automation container: 10.1.1.10
- FRR1: 10.1.1.11
- GoBGP1: 10.1.1.12
- Host1: 10.1.1.20
- Host2: 10.1.1.21

Data Plane: 10.0.1.0/29
- FRR1: 10.0.1.2
- GoBGP1: 10.0.1.3

Backend Networks:
- FRR1 backend: 10.1.0.0/24 (host1: 10.1.0.10)
- GoBGP1 backend: 10.2.0.0/24 (host2: 10.2.0.10)

BGP Configuration:
- FRR1: AS 65001, Router ID 1.1.1.1
- GoBGP1: AS 65002, Router ID 2.2.2.2
- Peer relationship over 10.0.1.0/29 data plane
- Route exchange for backend networks

## Components

### FRR Container Image (Build-Time Configuration)

Defined in [Dockerfile.frr](Dockerfile.frr). The following are configured at image build time:

- Base image: frrouting/frr:latest
- Enable BGP and Zebra daemons in /etc/frr/daemons
- Install SSH server packages (openssh-server, openssh-keygen, openssh-client)
- Configure SSH settings (PermitRootLogin, PasswordAuthentication)
- Set root password from FRR_ROOT_PASS build arg
- Create Ansible user from FRR_USER/FRR_PASS build args:
  - Add user to frrvty group (exists in base FRR image)
  - Set vtysh as default shell (required for Ansible frr.frr module)
- Create FRR config files with proper ownership (/etc/frr/bgpd.conf, /etc/frr/vtysh.conf)

Build command (executed automatically by setup scripts if image doesn't exist):

```bash
docker build -f Dockerfile.frr -t frr-ansible:latest \
    --build-arg FRR_ROOT_PASS="$FRR_ROOT_PASS" \
    --build-arg FRR_USER="$FRR_USER" \
    --build-arg FRR_PASS="$FRR_PASS" .
```

### FRR Container (Runtime Configuration)

Defined in [topology.yml](topology.yml) exec section. The following run when the container starts:

- `ssh-keygen -A`: Generate SSH host keys (must be unique per container instance)
- `/usr/lib/frr/frrinit.sh start`: Start FRR daemons (zebra, bgpd)
- `/usr/sbin/sshd`: Start SSH server for Ansible access

These cannot be done at build time because:
- SSH host keys must be unique per container instance
- FRR daemons require a running container with proper namespaces

### Automation Container

Defined in [Dockerfile.automation](Dockerfile.automation):
- Base image: python:3.11-slim
- System packages: openssh-client, sshpass, iputils-ping, iproute2, curl, vim, git
- Python packages: ansible, grpcio, grpcio-tools, protobuf, netmiko, paramiko
- Ansible collections: frr.frr, ansible.netcommon
- GoBGP gRPC stubs: clones gobgp repository, compiles proto files to Python stubs
- Working directory: /workspace

### Topology File

[topology.yml](topology.yml) defines network devices:
- Management network configuration
- Container images and management IPs for each node
- FRR runtime initialization (ssh-keygen, frrinit, sshd)
- GoBGP configuration:
  - Starts bgp daemon with no config (-f /dev/null)
  - Debug level logging
  - gRPC server on port 50051
- Host containers for connectivity testing

### Inventory File

[inventory.yml](inventory.yml) structure:
- FRR routers group:
  - Uses network_cli connection type
  - Credentials loaded from credentials.yml vars_file
  - Variables: ansible_host, bgp_as, bgp_router_id, bgp_neighbor_ip, bgp_neighbor_as, advertise_network
- GoBGP routers group:
  - Variables: ansible_host, bgp_as, bgp_router_id
  - No Ansible connection (configured via Python gRPC)

## Setup Process

### Entry Point: [setup.sh](setup.sh) (or [setup.ps1](setup.ps1) for Windows)

1. Source credentials.env and generate credentials.yml

2. Check if Docker images exist, build if needed:
   - network-automation:latest (automation container)
   - frr-ansible:latest (FRR with baked-in user credentials)

3. Destroy existing lab containers and mounted directories
   - Ensures clean state
   - Deploys fresh lab with topology.yml

4. Wait for containers to stabilize (5 seconds)

5. Configure data plane with [create-links.sh](create-links.sh)

6. Enable IP forwarding in GoBGP container kernel
   - Uses Alpine container in gobgp1 network namespace
   - Sets net.ipv4.ip_forward=1
   - Adds route to 10.1.0.0/24 via 10.0.1.2
   - Required because gobgp image only contains daemon with no shell

7. Copy files to automation container:
   - [configure_gobgp.py](configure_gobgp.py)
   - [config_playbook.yml](config_playbook.yml)
   - [inventory.yml](inventory.yml)
   - [credentials.yml](credentials.yml)

### Data Plane Configuration: [create-links.sh](create-links.sh)

Series of docker network commands:
- Cleans up networks and links from previous runs
- Creates Docker networks for data plane connectivity
- Creates links between gobgp and frr
- Assigns IP addresses to interfaces
- Creates backend networks (10.1.0.0/24 and 10.2.0.0/24)
- Connects host1 and host2 to respective backend networks
- Deletes default routes on hosts
- Adds default routes pointing to respective routers

### Generated Directory: clab-bgp-lab/

ContainerLab creates directory containing:
- ansible-inventory.yml: auto-generated inventory
- topology-data.json: lab topology metadata
- authorized_keys: SSH keys for container access

## Configuration Execution

After infrastructure setup completes, run configuration playbook:

```bash
docker exec -it clab-bgp-lab-automation ansible-playbook -i inventory.yml config_playbook.yml
```

### Configuration Playbook: [config_playbook.yml](config_playbook.yml)

The playbook handles BGP protocol configuration only. FRR user and daemon setup is already complete from the Docker image build and container startup.

#### Task 1: Configure GoBGP via Python/gRPC

Runs [configure_gobgp.py](configure_gobgp.py):
- Uses compiled gRPC stubs from automation image build
- Connects to gRPC server on 10.1.1.12:50051
- Sets router ID: 2.2.2.2
- Sets AS number: 65002
- Configures BGP neighbor:
  - Neighbor IP: 10.0.1.3 (GoBGP data plane IP)
  - Peer AS: 65001
  - Next hop: 10.0.1.3 (GoBGP data plane IP)
- Advertises network prefix: 10.2.0.0/24
- Configures import/export policies:
  - Accept all routes
  - Applied to neighbor for route exchange
- Adds path to global RIB (Route Information Base)
- Constructs BGP attributes using compiled API structures

#### Task 2: Configure FRR via Ansible

Uses frr.frr.frr_bgp module:
- Loads credentials from credentials.yml vars_file
- Sets AS number: 65001
- Sets router ID: 1.1.1.1
- Configures BGP neighbor:
  - Neighbor IP: 10.0.1.3 (GoBGP data plane IP)
  - Peer AS: 65002
- Advertises network: 10.1.0.0/24
  - Next hop: 10.0.1.2 (FRR data plane IP)
- Configures route-map to permit all routes

## Verification

### Quick GoBGP Status Check

[checkGobgpStatus.sh](checkGobgpStatus.sh) provides quick status:

```bash
./checkGobgpStatus.sh
```

Shows:
- BGP neighbor status
- Global RIB contents
- Routes received from FRR (adj-in)
- Routes advertised to FRR (adj-out)

### Comprehensive Verification

[verify-bgp.sh](verify-bgp.sh) performs full verification:

```bash
./verify-bgp.sh
```

Checks:
- FRR1 routing table (show ip route)
- FRR1 BGP summary (show bgp summary)
- FRR1 routes advertised to GoBGP
- GoBGP1 neighbor status
- GoBGP1 global RIB
- GoBGP1 routes received from FRR
- End-to-end connectivity:
  - Host1 (10.1.0.10) pings Host2 (10.2.0.10)
  - Host2 (10.2.0.10) pings Host1 (10.1.0.10)

### Expected End State

Successful configuration results in:
- BGP neighbor state: Established on both routers
- Route exchange:
  - FRR1 learns 10.2.0.0/24 from GoBGP1
  - GoBGP1 learns 10.1.0.0/24 from FRR1
- Routes present in routing tables (RIB)
- Host1 can ping Host2 through BGP routing
- Host2 can ping Host1 through BGP routing

## Troubleshooting

### Container Status

Check running containers:

```bash
docker ps
```

Expected containers:
- clab-bgp-lab-automation
- clab-bgp-lab-frr1
- clab-bgp-lab-gobgp1
- clab-bgp-lab-host1
- clab-bgp-lab-host2

### BGP Daemon Status

Check if BGP daemon is running in FRR:

```bash
docker exec clab-bgp-lab-frr1 ps | grep bgp
```

### Direct Container Access

Access FRR CLI:

```bash
docker exec -it clab-bgp-lab-frr1 vtysh
```

Access GoBGP CLI:

```bash
docker exec clab-bgp-lab-gobgp1 gobgp neighbor
docker exec clab-bgp-lab-gobgp1 gobgp global rib
```

### SSH Connectivity

Test SSH to FRR container (use credentials from credentials.env):

```bash
docker exec clab-bgp-lab-automation ssh <FRR_USER>@10.1.1.11
```

### ContainerLab Logs

View ContainerLab deployment logs:

```bash
docker logs <containerlab-container-id>
```

## Lab Teardown

Destroy lab and cleanup resources:

```bash
# Using ContainerLab directly
containerlab destroy -t topology.yml --cleanup

# Or via Docker
docker run --rm -it --privileged --network host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd):/lab -w /lab \
  ghcr.io/srl-labs/clab containerlab destroy -t topology.yml --cleanup
```

On Windows PowerShell:

```powershell
docker run --rm -it --privileged `
  --network host `
  -v /var/run/docker.sock:/var/run/docker.sock `
  -v ${PWD}:/lab `
  -w /lab `
  ghcr.io/srl-labs/clab containerlab destroy -t topology.yml --cleanup
```

## File Overview

- [topology.yml](topology.yml): ContainerLab topology definition
- [Dockerfile.automation](Dockerfile.automation): Custom automation container image
- [Dockerfile.frr](Dockerfile.frr): FRR container with baked-in Ansible user
- [inventory.yml](inventory.yml): Ansible inventory with router variables
- [credentials.env](credentials.env): Credentials source file (gitignored, create manually)
- [credentials.yml](credentials.yml): Ansible credentials (gitignored, auto-generated)
- [configure_gobgp.py](configure_gobgp.py): Python script for GoBGP gRPC configuration
- [config_playbook.yml](config_playbook.yml): Ansible playbook for BGP configuration
- [setup.sh](setup.sh): Main setup script (Linux/macOS)
- [setup.ps1](setup.ps1): Main setup script (Windows PowerShell)
- [create-links.sh](create-links.sh): Data plane network configuration
- [verify-bgp.sh](verify-bgp.sh): Comprehensive BGP verification script
- [checkGobgpStatus.sh](checkGobgpStatus.sh): Quick GoBGP status check
- clab-bgp-lab/: Generated directory with topology data and keys
