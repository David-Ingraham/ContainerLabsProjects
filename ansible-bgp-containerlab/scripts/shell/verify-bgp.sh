#!/bin/bash
# Verify BGP configuration and end-to-end connectivity

echo "=========================================="
echo "BGP Lab Verification"
echo "=========================================="

# Container names
FRR1="clab-bgp-lab-frr1"
FRR2="clab-bgp-lab-frr2"
GOBGP1="clab-bgp-lab-gobgp1"
HOST1="clab-bgp-lab-host1"
HOST2="clab-bgp-lab-host2"
RECEIVER1="clab-bgp-lab-receiver1"
RECEIVER2="clab-bgp-lab-receiver2"

echo ""
echo "=== Topology ==="
echo "                              [frr2 10.2.0.2] -------- [receiver1] [receiver2]"
echo "                                    |                  10.2.0.10   10.2.0.20"
echo "                                 10.1.0.3"
echo "                                    |"
echo "host1 (10.1.0.10) -- [frr1 10.1.0.2] --------- [gobgp1] -- host2 (10.3.0.10)"
echo "                                     10.0.1.x   10.3.0.2"

echo ""
echo "=========================================="
echo "FRR1 Status (AS 65001)"
echo "=========================================="

echo ""
echo "=== FRR1 BGP Summary ==="
docker exec $FRR1 vtysh -c "show bgp summary"

echo ""
echo "=== FRR1 Routing Table ==="
docker exec $FRR1 vtysh -c "show ip route"

echo ""
echo "=========================================="
echo "FRR2 Status (AS 65003)"
echo "=========================================="

echo ""
echo "=== FRR2 BGP Summary ==="
docker exec $FRR2 vtysh -c "show bgp summary"

echo ""
echo "=== FRR2 Routing Table ==="
docker exec $FRR2 vtysh -c "show ip route"

echo ""
echo "=========================================="
echo "GoBGP1 Status (AS 65002)"
echo "=========================================="

echo ""
echo "=== GoBGP1 Neighbor Status ==="
docker exec $GOBGP1 gobgp neighbor

echo ""
echo "=== GoBGP1 Global RIB ==="
docker exec $GOBGP1 gobgp global rib

echo ""
echo "=========================================="
echo "Connectivity Tests"
echo "=========================================="

# Test 1: Host1 -> Host2 (original path)
echo ""
echo "=== Test 1: Host1 (10.1.0.10) -> Host2 (10.3.0.10) ==="
echo "Path: host1 -> frr1 -> gobgp1 -> host2"
if docker exec $HOST1 ping -c 2 -W 2 10.3.0.10 > /dev/null 2>&1; then
    echo "PASS"
else
    echo "FAIL"
fi

# Test 2: Host2 -> Host1 (return path)
echo ""
echo "=== Test 2: Host2 (10.3.0.10) -> Host1 (10.1.0.10) ==="
echo "Path: host2 -> gobgp1 -> frr1 -> host1"
if docker exec $HOST2 ping -c 2 -W 2 10.1.0.10 > /dev/null 2>&1; then
    echo "PASS"
else
    echo "FAIL"
fi

# Test 3: Receiver1 -> Host1 (multicast path)
echo ""
echo "=== Test 3: Receiver1 (10.2.0.10) -> Host1 (10.1.0.10) ==="
echo "Path: receiver1 -> frr2 -> frr1 -> host1"
if docker exec $RECEIVER1 ping -c 2 -W 2 10.1.0.10 > /dev/null 2>&1; then
    echo "PASS"
else
    echo "FAIL"
fi

# Test 4: Host1 -> Receiver1 (multicast source to receiver)
echo ""
echo "=== Test 4: Host1 (10.1.0.10) -> Receiver1 (10.2.0.10) ==="
echo "Path: host1 -> frr1 -> frr2 -> receiver1"
if docker exec $HOST1 ping -c 2 -W 2 10.2.0.10 > /dev/null 2>&1; then
    echo "PASS"
else
    echo "FAIL"
fi

# Test 5: Receiver1 -> Host2 (cross network)
echo ""
echo "=== Test 5: Receiver1 (10.2.0.10) -> Host2 (10.3.0.10) ==="
echo "Path: receiver1 -> frr2 -> frr1 -> gobgp1 -> host2"
if docker exec $RECEIVER1 ping -c 2 -W 2 10.3.0.10 > /dev/null 2>&1; then
    echo "PASS"
else
    echo "FAIL"
fi

echo ""
echo "=========================================="
echo "Verification Complete"
echo "=========================================="
echo ""
