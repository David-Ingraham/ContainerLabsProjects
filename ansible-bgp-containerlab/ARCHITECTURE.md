# Lab Architecture

## Separation of Concerns

This lab separates **infrastructure** from **configuration**:

### Infrastructure Layer (setup.sh)
Handles the physical/virtual environment setup:
- Docker image building
- Container deployment
- Network interface creation
- IP address assignment to interfaces
- File distribution

**Tools:** Bash, Docker, ContainerLab

**Goal:** Ready-to-configure network lab

### Configuration Layer (Ansible + Python)
Handles protocol and service configuration:
- BGP AS numbers
- BGP router IDs
- BGP neighbor relationships
- Route advertisements

**Tools:** Ansible, Python gRPC, SSH

**Goal:** Working BGP network

## Network Topology

```
                  Management Network
                     10.1.1.0/24
                         |
        +----------------+----------------+
        |                |                |
   automation       frr1 (mgmt)      gobgp1 (mgmt)
   10.1.1.10        10.1.1.11         10.1.1.12
        |                |                |
        |                |                |
        |         Data Plane Network      |
        |            10.0.1.0/30          |
        |                |                |
        |           frr1:eth1 -------- gobgp1:eth1
        |            10.0.1.1         10.0.1.2
        |                                  
    Python/Ansible                         
    gRPC/SSH calls                         
```

## File Roles

**Infrastructure Files:**
- `Dockerfile.automation` - Custom image definition
- `topology.yml` - ContainerLab topology
- `create-links.sh` - Interface IP configuration
- `setup.sh` - Master infrastructure script

**Configuration Files:**
- `configure_gobgp.py` - GoBGP gRPC configuration
- `config_playbook.yml` - Ansible orchestration
- `inventory.yml` - Device inventory

**Documentation:**
- `README.md` - Project overview
- `HOWTO.md` - Step-by-step guide
- `ARCHITECTURE.md` - This file

## Configuration Methods by Device

**GoBGP:**
- Method: gRPC API
- From: automation container (10.1.1.10)
- To: 10.1.1.12:50051
- Protocol: Binary protobuf over HTTP/2
- Tool: Python with grpcio + gobgp libraries

**FRR:**
- Method: SSH with network_cli
- From: automation container (10.1.1.10)
- To: 10.1.1.11:22
- Protocol: SSH
- Tool: Ansible netcommon.cli_command module

## Why This Design?

**Scalability:**
- Management IPs don't conflict (not port-based)
- Add router: just assign new 10.1.1.x address
- Same API ports on all devices (50051, 22)

**Production-Like:**
- Separate management and data networks
- Automation from dedicated host
- API-based configuration (not CLI scraping)
- SSH for legacy devices

**Learning Value:**
- Understand network planes (management vs data)
- Practice gRPC API calls
- Use Ansible network modules properly
- See infrastructure vs configuration separation

