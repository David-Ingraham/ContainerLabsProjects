#!/bin/bash
# Verify BGP configuration and end-to-end connectivity

echo "=========================================="
echo "BGP Lab Verification"
echo "=========================================="

# Container names
FRR1="clab-bgp-lab-frr1"
GOBGP1="clab-bgp-lab-gobgp1"
HOST1="clab-bgp-lab-host1"
HOST2="clab-bgp-lab-host2"

echo ""
echo "=== FRR1 Routing Table ==="
docker exec $FRR1 vtysh -c "show ip route"

echo ""
echo "=== FRR1 BGP Summary ==="
docker exec $FRR1 vtysh -c "show bgp summary"

echo ""
echo "=== FRR1 Advertised Routes to GoBGP ==="
docker exec $FRR1 vtysh -c "show bgp ipv4 unicast neighbors 10.0.1.3 advertised-routes"

echo ""
echo "=== GoBGP1 Neighbor Status ==="
docker exec $GOBGP1 gobgp neighbor

echo ""
echo "=== GoBGP1 Global RIB ==="
docker exec $GOBGP1 gobgp global rib

echo ""
echo "=== GoBGP1 Routes Received from FRR ==="
docker exec $GOBGP1 gobgp neighbor 10.0.1.2 adj-in

echo ""
echo "=========================================="
echo "End-to-End Connectivity Test"
echo "=========================================="

echo ""
echo "=== Host1 (10.1.0.10) pinging Host2 (10.3.0.10) ==="
if docker exec $HOST1 ping -c 3 10.3.0.10; then
    echo "SUCCESS: Host1 can reach Host2 through BGP"
else
    echo "FAILED: Host1 cannot reach Host2"
fi

echo ""
echo "=== Host2 (10.3.0.10) pinging Host1 (10.1.0.10) ==="
if docker exec $HOST2 ping -c 3 10.1.0.10; then
    echo "SUCCESS: Host2 can reach Host1 through BGP"
else
    echo "FAILED: Host2 cannot reach Host1"
fi

echo ""
echo "=========================================="
echo "Verification Complete"
echo "=========================================="

