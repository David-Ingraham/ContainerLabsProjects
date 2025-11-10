#!/bin/bash
# Create network links between containers using Docker networks

set -e  # Exit on any error

echo "Creating network links..."

# Container names
CLIENT1="clab-multi-vendor-api-bgp-client1"
FRR1="clab-multi-vendor-api-bgp-frr1"
GOBGP1="clab-multi-vendor-api-bgp-gobgp1"
CLIENT2="clab-multi-vendor-api-bgp-client2"

# Disconnect containers from old networks first
echo "Cleaning up old connections..."
docker network disconnect link-client1-frr1 $CLIENT1 2>/dev/null || true
docker network disconnect link-client1-frr1 $FRR1 2>/dev/null || true
docker network disconnect link-frr1-gobgp1 $FRR1 2>/dev/null || true
docker network disconnect link-frr1-gobgp1 $GOBGP1 2>/dev/null || true
docker network disconnect link-gobgp1-client2 $GOBGP1 2>/dev/null || true
docker network disconnect link-gobgp1-client2 $CLIENT2 2>/dev/null || true

# Remove old networks
docker network rm link-client1-frr1 2>/dev/null || true
docker network rm link-frr1-gobgp1 2>/dev/null || true
docker network rm link-gobgp1-client2 2>/dev/null || true

# Create networks with /29 subnet (Docker uses .1 as gateway, we use .2 and .3)
echo "Creating Docker networks..."
docker network create --subnet=10.0.1.0/29 link-client1-frr1
docker network create --subnet=10.0.2.0/29 link-frr1-gobgp1
docker network create --subnet=10.0.3.0/29 link-gobgp1-client2

# Connect containers (skip .1 which Docker uses as gateway)
echo "Connecting containers to networks..."
docker network connect --ip 10.0.1.2 link-client1-frr1 $CLIENT1
docker network connect --ip 10.0.1.3 link-client1-frr1 $FRR1

docker network connect --ip 10.0.2.2 link-frr1-gobgp1 $FRR1
docker network connect --ip 10.0.2.3 link-frr1-gobgp1 $GOBGP1

docker network connect --ip 10.0.3.2 link-gobgp1-client2 $GOBGP1
docker network connect --ip 10.0.3.3 link-gobgp1-client2 $CLIENT2

echo "Links created successfully!"
echo ""
echo "Verify with: docker exec $CLIENT1 ip addr"
