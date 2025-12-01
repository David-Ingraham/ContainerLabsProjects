# Verify BGP configuration and end-to-end connectivity

$ErrorActionPreference = "Continue"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "BGP Lab Verification" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Container names
$FRR1 = "clab-multicast-lab-frr1"
$GOBGP1 = "clab-multicast-lab-gobgp1"
$HOST1 = "clab-multicast-lab-host1"
$HOST2 = "clab-multicast-lab-host2"

Write-Host ""
Write-Host "=== FRR1 Routing Table ===" -ForegroundColor Yellow
docker exec $FRR1 vtysh -c "show ip route"

Write-Host ""
Write-Host "=== FRR1 BGP Summary ===" -ForegroundColor Yellow
docker exec $FRR1 vtysh -c "show bgp summary"

Write-Host ""
Write-Host "=== FRR1 Advertised Routes to GoBGP ===" -ForegroundColor Yellow
docker exec $FRR1 vtysh -c "show bgp ipv4 unicast neighbors 10.0.1.3 advertised-routes"

Write-Host ""
Write-Host "=== GoBGP1 Neighbor Status ===" -ForegroundColor Yellow
docker exec $GOBGP1 gobgp neighbor

Write-Host ""
Write-Host "=== GoBGP1 Global RIB ===" -ForegroundColor Yellow
docker exec $GOBGP1 gobgp global rib

Write-Host ""
Write-Host "=== GoBGP1 Routes Received from FRR ===" -ForegroundColor Yellow
docker exec $GOBGP1 gobgp neighbor 10.0.1.2 adj-in

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "End-to-End Connectivity Test" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "=== Host1 (10.1.0.10) pinging Host2 (10.2.0.10) ===" -ForegroundColor Yellow
docker exec $HOST1 ping -c 3 10.2.0.10
if ($LASTEXITCODE -eq 0) {
    Write-Host "SUCCESS: Host1 can reach Host2 through BGP!" -ForegroundColor Green
} else {
    Write-Host "FAILED: Host1 cannot reach Host2" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Host2 (10.2.0.10) pinging Host1 (10.1.0.10) ===" -ForegroundColor Yellow
docker exec $HOST2 ping -c 3 10.1.0.10
if ($LASTEXITCODE -eq 0) {
    Write-Host "SUCCESS: Host2 can reach Host1 through BGP!" -ForegroundColor Green
} else {
    Write-Host "FAILED: Host2 cannot reach Host1" -ForegroundColor Red
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Verification Complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

