# Verify multicast configuration and routing state

$LAB_NAME = "bgp-lab"
$FRR1 = "clab-$LAB_NAME-frr1"
$FRR2 = "clab-$LAB_NAME-frr2"

Write-Host "============================================"
Write-Host "Multicast Verification"
Write-Host "============================================"
Write-Host ""

# Check PIM neighbors
Write-Host "=== PIM Neighbors ==="
Write-Host ""
Write-Host "frr1:"
docker exec "$FRR1" vtysh -c "show ip pim neighbor"
Write-Host ""
Write-Host "frr2:"
docker exec "$FRR2" vtysh -c "show ip pim neighbor"
Write-Host ""

# Check PIM interfaces
Write-Host "=== PIM Interfaces ==="
Write-Host ""
Write-Host "frr1:"
docker exec "$FRR1" vtysh -c "show ip pim interface"
Write-Host ""
Write-Host "frr2:"
docker exec "$FRR2" vtysh -c "show ip pim interface"
Write-Host ""

# Check RP info
Write-Host "=== PIM RP Information ==="
Write-Host ""
Write-Host "frr1:"
docker exec "$FRR1" vtysh -c "show ip pim rp-info"
Write-Host ""
Write-Host "frr2:"
docker exec "$FRR2" vtysh -c "show ip pim rp-info"
Write-Host ""

# Check IGMP groups
Write-Host "=== IGMP Groups ==="
Write-Host ""
Write-Host "frr2 (LHR):"
docker exec "$FRR2" vtysh -c "show ip igmp groups"
Write-Host ""

# Check multicast routing table
Write-Host "=== Multicast Routes (mroute) ==="
Write-Host ""
Write-Host "frr1 (FHR):"
docker exec "$FRR1" vtysh -c "show ip mroute"
Write-Host ""
Write-Host "frr2 (LHR):"
docker exec "$FRR2" vtysh -c "show ip mroute"
Write-Host ""

# Check PIM state
Write-Host "=== PIM State ==="
Write-Host ""
Write-Host "frr1:"
docker exec "$FRR1" vtysh -c "show ip pim state"
Write-Host ""
Write-Host "frr2:"
docker exec "$FRR2" vtysh -c "show ip pim state"
Write-Host ""

Write-Host "============================================"
Write-Host "Verification complete"
Write-Host "============================================"
