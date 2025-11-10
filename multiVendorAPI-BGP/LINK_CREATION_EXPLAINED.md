# Network Link Creation - Docker Native Networking Approach

## What This Script Does

Creates network connections between Docker containers using Docker's native networking features instead of manual veth pair manipulation.

## Why Docker Native Networking?

**Problem with veth pairs on Docker Desktop:**
- Docker Desktop (macOS/Windows) runs containers in a Linux VM
- PID namespace isolation prevents direct veth pair manipulation
- `nsenter` commands fail because PIDs from `docker inspect` aren't accessible from WSL or containerlab containers
- After moving one end of veth pair into a container, the other end mysteriously disappears

**Solution - Docker Networks:**
- Uses `docker network create` to create bridge networks
- Uses `docker network connect` to attach containers
- Platform-independent: works identically on macOS, Windows/WSL, and native Linux
- No PID/namespace manipulation required

## Network Architecture

### /29 Subnets
Each link uses a /29 subnet (6 usable IPs):
- `.0` - Network address (reserved)
- `.1` - Docker gateway (reserved but unused)
- `.2` - First container
- `.3` - Second container
- `.4-.6` - Unused
- `.7` - Broadcast address (reserved)

### Three Links
```
client1 (.2) <--[10.0.1.0/29]--> frr1 (.3)
frr1 (.2)    <--[10.0.2.0/29]--> gobgp1 (.3)
gobgp1 (.2)  <--[10.0.3.0/29]--> client2 (.3)
```

## How the Script Works

### 1. Cleanup Phase
```bash
docker network disconnect link-client1-frr1 $CLIENT1 2>/dev/null || true
docker network rm link-client1-frr1 2>/dev/null || true
```
- Disconnects containers from old networks
- Removes old network bridges
- `2>/dev/null || true` = ignore errors if networks don't exist

### 2. Network Creation
```bash
docker network create --subnet=10.0.1.0/29 link-client1-frr1
```
- Creates a bridge network with specified subnet
- Docker automatically assigns `.1` as the gateway IP
- Returns network ID on success

### 3. Container Connection
```bash
docker network connect --ip 10.0.1.2 link-client1-frr1 $CLIENT1
docker network connect --ip 10.0.1.3 link-client1-frr1 $FRR1
```
- Attaches containers to the network
- Assigns specific IP addresses
- Creates new network interfaces inside containers (eth1, eth2, etc.)
- Interfaces are automatically brought up

## Key Benefits

1. **Platform Independence**: Works on all Docker platforms
2. **Simplicity**: No PID manipulation or namespace gymnastics
3. **Reliability**: Uses Docker's built-in networking (well-tested)
4. **Error Handling**: `set -e` stops on first error
5. **Idempotent**: Can run multiple times safely (cleanup first)

## Common Issues

### "Address already in use"
**Cause:** Docker's gateway IP conflicts with container IP

**Solution:** Use /29 or larger subnets. Docker always takes `.1` as gateway, so use `.2`, `.3`, etc. for containers.

### Containerlab link creation fails
**Symptom:**
```
ERRO failed deploy links for node: failed to Statfs "/proc/xxxx/ns/net"
```

**Cause:** Race condition - containerlab tries to create links before container namespaces are ready

**Solution:** Let containerlab fail, then use this script to create links via Ansible playbook

## Comparison: veth vs Docker Networks

| Feature | veth Pairs | Docker Networks |
|---------|-----------|----------------|
| Platform Support | Native Linux only | All platforms |
| Requires Privileges | Yes (--privileged + --pid=host) | Yes (--privileged) |
| Complexity | High (PID/namespace manipulation) | Low (simple commands) |
| Docker Desktop Support | Broken (PID isolation) | Works perfectly |
| Debugging | Difficult (namespace issues) | Easy (standard Docker commands) |

## Testing Connectivity

After script runs successfully:

```bash
# Check interfaces created
docker exec clab-multi-vendor-api-bgp-client1 ip addr

# Check networks
docker network ls | grep link-

# Test end-to-end
docker exec clab-multi-vendor-api-bgp-client1 ping -c 3 10.0.3.3
```

## Script Location

Integrated into Ansible playbook: `bgp-config.yml`

Runs as: 
```bash
docker run --rm --privileged \
  --network=host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /mnt/c/ContainerLabsProjects/multiVendorAPI-BGP:/workspace \
  ghcr.io/srl-labs/clab sh /workspace/create-links.sh
```

No special tools needed - just Docker CLI and bash!
