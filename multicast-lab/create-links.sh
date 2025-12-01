#!/bin/bash
# Create data plane link between FRR1 and GoBGP1
# Uses Docker networks (workaround for ContainerLab link failures on macOS)

set -e

echo "Creating data plane network..."

# Container names
FRR1="clab-multicast-lab-frr1"
GOBGP1="clab-multicast-lab-gobgp1"
NETWORK="multicast-lab-dataplane"

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
        
        # Disconnect all containers from the conflicting network first
        for container in $(docker network inspect $net --format '{{range .Containers}}{{.Name}} {{end}}'); do
            echo "    Disconnecting container: $container"
            docker network disconnect $net $container 2>/dev/null || true
        done
        
        # Now remove the network
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

# Create backend networks for BGP route advertisement
echo ""
echo "Creating backend networks..."
# Note: Docker reserves .1 for bridge gateway, so we use .2 for routers
docker network create --subnet=10.1.0.0/24 multicast-lab-frr-network 2>/dev/null || true
docker network connect --ip 10.1.0.2 multicast-lab-frr-network $FRR1 2>/dev/null || true
docker network connect --ip 10.1.0.10 multicast-lab-frr-network clab-multicast-lab-host1 2>/dev/null || true

docker network create --subnet=10.2.0.0/24 multicast-lab-gobgp-network 2>/dev/null || true
docker network connect --ip 10.2.0.2 multicast-lab-gobgp-network $GOBGP1 2>/dev/null || true
docker network connect --ip 10.2.0.10 multicast-lab-gobgp-network clab-multicast-lab-host2 2>/dev/null || true

#deleting the default route given to it by docker
docker exec clab-multicast-lab-host1 ip route del default 2>/dev/null || true
docker exec clab-multicast-lab-host2 ip route del default 2>/dev/null || true


docker exec clab-multicast-lab-host1 ip route add default via 10.1.0.2 2>/dev/null || true
docker exec clab-multicast-lab-host2 ip route add default via 10.2.0.2 2>/dev/null || true
echo "Backend networks configured (FRR: 10.1.0.2, GoBGP: 10.2.0.2)"
