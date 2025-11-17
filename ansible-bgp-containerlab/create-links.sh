#!/bin/bash
# Create data plane link between FRR1 and GoBGP1
# Uses Docker networks (workaround for ContainerLab link failures on macOS)

set -e

echo "Creating data plane network..."

# Container names
FRR1="clab-bgp-lab-frr1"
GOBGP1="clab-bgp-lab-gobgp1"
NETWORK="bgp-dataplane"

# Clean up old network if exists
echo "Cleaning up old connections..."
docker network disconnect $NETWORK $FRR1 2>/dev/null || true
docker network disconnect $NETWORK $GOBGP1 2>/dev/null || true
docker network rm $NETWORK 2>/dev/null || true

# Find and remove any networks using 10.0.1.0 subnet
echo "Checking for conflicting networks..."
for net in $(docker network ls --format "{{.Name}}"); do
    if docker network inspect $net 2>/dev/null | grep -q "10.0.1.0"; then
        echo "  Removing conflicting network: $net"
        docker network rm $net 2>/dev/null || true
    fi
done

# Create Docker network for data plane (using /29 to avoid gateway conflict)
# Docker uses .1 as gateway, so we use .2 and .3 for routers
echo "Creating data plane Docker network..."
docker network create --subnet=10.0.1.0/29 $NETWORK

# Connect containers with static IPs
echo "Connecting routers to data plane..."
docker network connect --ip 10.0.1.2 $NETWORK $FRR1
docker network connect --ip 10.0.1.3 $NETWORK $GOBGP1

echo ""
echo "Data plane configured:"
echo "  Docker gateway: 10.0.1.1/29"
echo "  frr1:           10.0.1.2/29"
echo "  gobgp1:         10.0.1.3/29"
echo ""
echo "Verifying connectivity..."
docker exec $FRR1 ping -c 2 10.0.1.3 || echo "Note: Ping may fail until routing is configured"

