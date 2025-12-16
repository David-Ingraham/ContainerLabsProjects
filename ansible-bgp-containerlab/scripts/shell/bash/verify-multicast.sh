#!/bin/bash
# Verify multicast configuration and routing state

LAB_NAME="bgp-lab"
FRR1="clab-${LAB_NAME}-frr1"
FRR2="clab-${LAB_NAME}-frr2"

echo "============================================"
echo "Multicast Verification"
echo "============================================"
echo ""

# Check PIM neighbors
echo "=== PIM Neighbors ==="
echo ""
echo "frr1:"
docker exec "$FRR1" vtysh -c "show ip pim neighbor"
echo ""
echo "frr2:"
docker exec "$FRR2" vtysh -c "show ip pim neighbor"
echo ""

# Check PIM interfaces
echo "=== PIM Interfaces ==="
echo ""
echo "frr1:"
docker exec "$FRR1" vtysh -c "show ip pim interface"
echo ""
echo "frr2:"
docker exec "$FRR2" vtysh -c "show ip pim interface"
echo ""

# Check RP info
echo "=== PIM RP Information ==="
echo ""
echo "frr1:"
docker exec "$FRR1" vtysh -c "show ip pim rp-info"
echo ""
echo "frr2:"
docker exec "$FRR2" vtysh -c "show ip pim rp-info"
echo ""

# Check IGMP groups
echo "=== IGMP Groups ==="
echo ""
echo "frr2 (LHR):"
docker exec "$FRR2" vtysh -c "show ip igmp groups"
echo ""

# Check multicast routing table
echo "=== Multicast Routes (mroute) ==="
echo ""
echo "frr1 (FHR):"
docker exec "$FRR1" vtysh -c "show ip mroute"
echo ""
echo "frr2 (LHR):"
docker exec "$FRR2" vtysh -c "show ip mroute"
echo ""

# Check PIM state
echo "=== PIM State ==="
echo ""
echo "frr1:"
docker exec "$FRR1" vtysh -c "show ip pim state"
echo ""
echo "frr2:"
docker exec "$FRR2" vtysh -c "show ip pim state"
echo ""

echo "============================================"
echo "Verification complete"
echo "============================================"

