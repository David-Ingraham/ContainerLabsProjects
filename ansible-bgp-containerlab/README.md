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

## Deploy

```bash
docker run --rm -it --privileged \
  --network host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd):/lab \
  -w /lab \
  ghcr.io/srl-labs/clab containerlab deploy -t topology.yml
```

## Access Routers

Devices are reachable at their management IPs:
- frr1: `10.1.1.11`
- gobgp1: `10.1.1.12:50051` (gRPC API)

## Configure

Configure routers programmatically using Python/Ansible against their management IPs.

No port forwarding needed - all routers on same management network.

