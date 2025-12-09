# Verify BGP configuration and end-to-end connectivity

$ErrorActionPreference = "Continue"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "BGP Lab Verification" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Container names
$FRR1 = "clab-bgp-lab-frr1"
$FRR2 = "clab-bgp-lab-frr2"
$GOBGP1 = "clab-bgp-lab-gobgp1"
$HOST1 = "clab-bgp-lab-host1"
$HOST2 = "clab-bgp-lab-host2"
$RECEIVER1 = "clab-bgp-lab-receiver1"
$RECEIVER2 = "clab-bgp-lab-receiver2"

Write-Host ""
Write-Host "=== Topology ===" -ForegroundColor Cyan
Write-Host "                              [frr2 10.2.0.2] -------- [receiver1] [receiver2]"
Write-Host "                                    |                  10.2.0.10   10.2.0.20"
Write-Host "                                 10.1.0.3"
Write-Host "                                    |"
Write-Host "host1 (10.1.0.10) -- [frr1 10.1.0.2] --------- [gobgp1] -- host2 (10.3.0.10)"
Write-Host "                                     10.0.1.x   10.3.0.2"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "FRR1 Status (AS 65001)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "=== FRR1 BGP Summary ===" -ForegroundColor Yellow
docker exec $FRR1 vtysh -c "show bgp summary"

Write-Host ""
Write-Host "=== FRR1 Routing Table ===" -ForegroundColor Yellow
docker exec $FRR1 vtysh -c "show ip route"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "FRR2 Status (AS 65003)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "=== FRR2 BGP Summary ===" -ForegroundColor Yellow
docker exec $FRR2 vtysh -c "show bgp summary"

Write-Host ""
Write-Host "=== FRR2 Routing Table ===" -ForegroundColor Yellow
docker exec $FRR2 vtysh -c "show ip route"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "GoBGP1 Status (AS 65002)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "=== GoBGP1 Neighbor Status ===" -ForegroundColor Yellow
docker exec $GOBGP1 gobgp neighbor

Write-Host ""
Write-Host "=== GoBGP1 Global RIB ===" -ForegroundColor Yellow
docker exec $GOBGP1 gobgp global rib

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Connectivity Tests" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Test 1: Host1 -> Host2 (original path)
Write-Host ""
Write-Host "=== Test 1: Host1 (10.1.0.10) -> Host2 (10.3.0.10) ===" -ForegroundColor Yellow
Write-Host "Path: host1 -> frr1 -> gobgp1 -> host2"
$result = docker exec $HOST1 ping -c 2 -W 2 10.3.0.10 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "PASS" -ForegroundColor Green
} else {
    Write-Host "FAIL" -ForegroundColor Red
}

# Test 2: Host2 -> Host1 (return path)
Write-Host ""
Write-Host "=== Test 2: Host2 (10.3.0.10) -> Host1 (10.1.0.10) ===" -ForegroundColor Yellow
Write-Host "Path: host2 -> gobgp1 -> frr1 -> host1"
$result = docker exec $HOST2 ping -c 2 -W 2 10.1.0.10 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "PASS" -ForegroundColor Green
} else {
    Write-Host "FAIL" -ForegroundColor Red
}

# Test 3: Receiver1 -> Host1 (multicast path)
Write-Host ""
Write-Host "=== Test 3: Receiver1 (10.2.0.10) -> Host1 (10.1.0.10) ===" -ForegroundColor Yellow
Write-Host "Path: receiver1 -> frr2 -> frr1 -> host1"
$result = docker exec $RECEIVER1 ping -c 2 -W 2 10.1.0.10 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "PASS" -ForegroundColor Green
} else {
    Write-Host "FAIL" -ForegroundColor Red
}

# Test 4: Host1 -> Receiver1 (multicast source to receiver)
Write-Host ""
Write-Host "=== Test 4: Host1 (10.1.0.10) -> Receiver1 (10.2.0.10) ===" -ForegroundColor Yellow
Write-Host "Path: host1 -> frr1 -> frr2 -> receiver1"
$result = docker exec $HOST1 ping -c 2 -W 2 10.2.0.10 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "PASS" -ForegroundColor Green
} else {
    Write-Host "FAIL" -ForegroundColor Red
}

# Test 5: Receiver1 -> Host2 (cross network)
Write-Host ""
Write-Host "=== Test 5: Receiver1 (10.2.0.10) -> Host2 (10.3.0.10) ===" -ForegroundColor Yellow
Write-Host "Path: receiver1 -> frr2 -> frr1 -> gobgp1 -> host2"
$result = docker exec $RECEIVER1 ping -c 2 -W 2 10.3.0.10 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "PASS" -ForegroundColor Green
} else {
    Write-Host "FAIL" -ForegroundColor Red
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Verification Complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
