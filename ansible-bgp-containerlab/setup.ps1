# Complete lab setup: build image, deploy containers, configure infrastructure

$ErrorActionPreference = "Stop"

$PROJECT_DIR = $PSScriptRoot
$AUTOMATION_IMAGE = "network-automation:latest"
$FRR_IMAGE = "frr-ansible:latest"
$LAB_NAME = "bgp-lab"

Set-Location $PROJECT_DIR

# Source credentials from env file
$credentialsFile = Join-Path $PROJECT_DIR "credentials.env"
if (Test-Path $credentialsFile) {
    Get-Content $credentialsFile | ForEach-Object {
        if ($_ -match "^\s*([^#][^=]+)=(.*)$") {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            Set-Variable -Name $name -Value $value -Scope Script
        }
    }
} else {
    Write-Host "ERROR: credentials.env not found" -ForegroundColor Red
    Write-Host "Create credentials.env with FRR_ROOT_PASS, FRR_USER, FRR_PASS"
    exit 1
}

# Generate credentials.yml for Ansible from env vars
$credentialsYml = @"
# Ansible credentials for FRR routers
# Auto-generated from credentials.env - do not edit directly
ansible_user: $FRR_USER
ansible_password: $FRR_PASS
"@
Set-Content -Path (Join-Path $PROJECT_DIR "credentials.yml") -Value $credentialsYml

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "BGP Lab Infrastructure Setup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Step 1: Check if custom images exist, build if needed
Write-Host ""
Write-Host "=== Step 1: Docker Images ===" -ForegroundColor Yellow

# Automation container image
$automationImageExists = docker images --format "{{.Repository}}:{{.Tag}}" | Select-String "network-automation:latest"
if ($automationImageExists) {
    Write-Host "Image $AUTOMATION_IMAGE exists" -ForegroundColor Green
} else {
    Write-Host "Building $AUTOMATION_IMAGE..." -ForegroundColor Yellow
    docker build -f Dockerfile.automation -t $AUTOMATION_IMAGE .
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Image $AUTOMATION_IMAGE built" -ForegroundColor Green
    } else {
        throw "Failed to build automation Docker image"
    }
}

# FRR container image (with credentials from env)
$frrImageExists = docker images --format "{{.Repository}}:{{.Tag}}" | Select-String "frr-ansible:latest"
if ($frrImageExists) {
    Write-Host "Image $FRR_IMAGE exists" -ForegroundColor Green
} else {
    Write-Host "Building $FRR_IMAGE..." -ForegroundColor Yellow
    docker build -f Dockerfile.frr -t $FRR_IMAGE `
        --build-arg FRR_ROOT_PASS="$FRR_ROOT_PASS" `
        --build-arg FRR_USER="$FRR_USER" `
        --build-arg FRR_PASS="$FRR_PASS" .
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Image $FRR_IMAGE built" -ForegroundColor Green
    } else {
        throw "Failed to build FRR Docker image"
    }
}

# Step 2: Deploy lab (destroy if running to ensure latest topology)
Write-Host ""
Write-Host "=== Step 2: Lab Deployment ===" -ForegroundColor Yellow
$labRunning = docker ps --format "{{.Names}}" | Select-String "clab-$LAB_NAME"
if ($labRunning) {
    Write-Host "Existing lab detected - destroying to ensure latest topology..." -ForegroundColor Yellow
    docker run --rm -it --privileged `
      --network host `
      -v /var/run/docker.sock:/var/run/docker.sock `
      -v ${PWD}:/lab `
      -w /lab `
      ghcr.io/srl-labs/clab containerlab destroy -t topology.yml --cleanup
    Write-Host "Old lab destroyed" -ForegroundColor Green
}

Write-Host "Deploying fresh lab..." -ForegroundColor Yellow
docker run --rm -it --privileged `
  --network host `
  -v /var/run/docker.sock:/var/run/docker.sock `
  -v ${PWD}:/lab `
  -w /lab `
  ghcr.io/srl-labs/clab containerlab deploy -t topology.yml

if ($LASTEXITCODE -eq 0) {
    Write-Host "Lab deployed" -ForegroundColor Green
} else {
    throw "Failed to deploy lab"
}

# Step 3: Wait for containers to stabilize
Write-Host ""
Write-Host "=== Step 3: Container Stabilization ===" -ForegroundColor Yellow
Write-Host "Waiting for containers to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 5
Write-Host "Containers ready" -ForegroundColor Green

# Step 4: Configure data plane using Python script
Write-Host ""
Write-Host "=== Step 4: Data Plane Configuration ===" -ForegroundColor Yellow
Write-Host "Configuring data plane networks from inventory.yml..." -ForegroundColor Yellow

# Legacy bash script via Docker (replaced by Python)
# docker run --rm `
#   -v /var/run/docker.sock:/var/run/docker.sock `
#   -v "${PROJECT_DIR}:/workspace" `
#   -w /workspace `
#   docker:cli sh create-links.sh

# Data-driven approach: read network config from inventory.yml
python create_links.py

if ($LASTEXITCODE -eq 0) {
    Write-Host "Data plane configured" -ForegroundColor Green
} else {
    Write-Host "Warning: Data plane configuration had issues, but continuing..." -ForegroundColor Yellow
}

# enabling ip forwarding in kernel of gobgp1
docker run --rm `
  --network container:clab-bgp-lab-gobgp1 `
  --privileged `
  alpine sh -c "sysctl -w net.ipv4.ip_forward=1 && ip route add 10.1.0.0/24 via 10.0.1.2"

# Step 5: Copy configuration files to automation container
Write-Host ""
Write-Host "=== Step 5: Configuration Files ===" -ForegroundColor Yellow
Write-Host "Copying files to automation container..." -ForegroundColor Yellow

docker exec clab-$LAB_NAME-automation mkdir -p /workspace 2>$null

docker cp configure_gobgp.py clab-$LAB_NAME-automation:/workspace/
docker cp config_playbook.yml clab-$LAB_NAME-automation:/workspace/
docker cp inventory.yml clab-$LAB_NAME-automation:/workspace/
docker cp credentials.yml clab-$LAB_NAME-automation:/workspace/

Write-Host "Files copied" -ForegroundColor Green

# Final status
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Infrastructure Setup Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Lab Status:" -ForegroundColor Green
Write-Host "  - Management Network: 10.1.1.0/24"
Write-Host "    - Automation:  10.1.1.10"
Write-Host "    - FRR1:        10.1.1.11"
Write-Host "    - GoBGP1:      10.1.1.12"
Write-Host "    - Host1:       10.1.1.20"
Write-Host "    - Host2:       10.1.1.21"
Write-Host ""
Write-Host "  - BGP Data Plane: 10.0.1.0/29"
Write-Host "    - FRR1 <-> GoBGP1"
Write-Host ""
Write-Host "  - Backend Networks:"
Write-Host "    - FRR1 backend:   10.1.0.0/24 (FRR: 10.1.0.2, host1: 10.1.0.10)"
Write-Host "    - GoBGP1 backend: 10.2.0.0/24 (GoBGP: 10.2.0.2, host2: 10.2.0.10)"
Write-Host ""
Write-Host "Configure BGP:" -ForegroundColor Yellow
Write-Host "  docker exec -it clab-$LAB_NAME-automation ansible-playbook -i inventory.yml config_playbook.yml"
