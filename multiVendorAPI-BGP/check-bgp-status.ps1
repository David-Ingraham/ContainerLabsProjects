# check-bgp-status.ps1
# Script to verify BGP configuration and routing

Write-Host "`n=== BGP Status Check ===" -ForegroundColor Cyan

# FRR1 BGP Summary
Write-Host "`n--- FRR1 BGP Summary ---" -ForegroundColor Yellow
docker exec clab-multi-vendor-api-bgp-frr1 vtysh -c "show bgp summary"

# FRR1 BGP Routes
Write-Host "`n--- FRR1 BGP Routes ---" -ForegroundColor Yellow
docker exec clab-multi-vendor-api-bgp-frr1 vtysh -c "show ip bgp"

# FRR1 Routing Table
Write-Host "`n--- FRR1 Routing Table ---" -ForegroundColor Yellow
docker exec clab-multi-vendor-api-bgp-frr1 vtysh -c "show ip route"

# FRR1 Interfaces
Write-Host "`n--- FRR1 Interfaces ---" -ForegroundColor Yellow
docker exec clab-multi-vendor-api-bgp-frr1 ip addr show

# GoBGP1 Neighbors
Write-Host "`n--- GoBGP1 Neighbors ---" -ForegroundColor Yellow
docker exec clab-multi-vendor-api-bgp-gobgp1 gobgp neighbor

# GoBGP1 Routes
Write-Host "`n--- GoBGP1 Global RIB ---" -ForegroundColor Yellow
docker exec clab-multi-vendor-api-bgp-gobgp1 gobgp global rib

# GoBGP1 Interfaces
Write-Host "`n--- GoBGP1 Interfaces ---" -ForegroundColor Yellow
docker exec clab-multi-vendor-api-bgp-gobgp1 ip addr show

# Client1 Routing Table
Write-Host "`n--- Client1 Routes ---" -ForegroundColor Yellow
docker exec clab-multi-vendor-api-bgp-client1 ip route

# Client2 Routing Table
Write-Host "`n--- Client2 Routes ---" -ForegroundColor Yellow
docker exec clab-multi-vendor-api-bgp-client2 ip route

# Connectivity Test
Write-Host "`n--- Connectivity Test (Client1 -> Client2) ---" -ForegroundColor Yellow
docker exec clab-multi-vendor-api-bgp-client1 ping -c 3 10.0.3.3

Write-Host "`n=== Check Complete ===" -ForegroundColor Green