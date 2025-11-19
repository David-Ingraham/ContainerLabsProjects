# Complete lab setup: build image, deploy containers, configure infrastructure

$ErrorActionPreference = "Stop"

$PROJECT_DIR = $PSScriptRoot
$IMAGE_NAME = "network-automation:latest"
$LAB_NAME = "bgp-lab"

Set-Location $PROJECT_DIR

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "BGP Lab Infrastructure Setup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Step 1: Check if custom image exists, build if needed
Write-Host ""
Write-Host "=== Step 1: Docker Image ===" -ForegroundColor Yellow
$imageExists = docker images --format "{{.Repository}}:{{.Tag}}" | Select-String "network-automation:latest"
if ($imageExists) {
    Write-Host "[OK] Image $IMAGE_NAME already exists" -ForegroundColor Green
} else {
    Write-Host "Building $IMAGE_NAME (one-time operation)..." -ForegroundColor Yellow
    docker build -f Dockerfile.automation -t $IMAGE_NAME .
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Image built successfully" -ForegroundColor Green
    } else {
        throw "Failed to build Docker image"
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
    Write-Host "[OK] Old lab destroyed" -ForegroundColor Green
}

Write-Host "Deploying fresh lab..." -ForegroundColor Yellow
docker run --rm -it --privileged `
  --network host `
  -v /var/run/docker.sock:/var/run/docker.sock `
  -v ${PWD}:/lab `
  -w /lab `
  ghcr.io/srl-labs/clab containerlab deploy -t topology.yml

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Lab deployed" -ForegroundColor Green
} else {
    throw "Failed to deploy lab"
}

# Step 3: Wait for containers to stabilize
Write-Host ""
Write-Host "=== Step 3: Container Stabilization ===" -ForegroundColor Yellow
Write-Host "Waiting for containers to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 5
Write-Host "[OK] Containers ready" -ForegroundColor Green

# Step 4: Configure data plane using Docker CLI container
Write-Host ""
Write-Host "=== Step 4: Data Plane Configuration ===" -ForegroundColor Yellow
Write-Host "Running create-links script via Docker CLI container..." -ForegroundColor Yellow

# Run create-links.sh from a container that has Docker installed
# This allows the script to create networks and connect containers
# Use $PROJECT_DIR which is set to $PSScriptRoot at the top
docker run --rm `
  -v /var/run/docker.sock:/var/run/docker.sock `
  -v "${PROJECT_DIR}:/workspace" `
  -w /workspace `
  docker:cli sh create-links.sh

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Data plane configured" -ForegroundColor Green
} else {
    Write-Host "Warning: Data plane configuration had issues, but continuing..." -ForegroundColor Yellow
}

# Step 5: Copy configuration files to automation container
Write-Host ""
Write-Host "=== Step 5: Configuration Files ===" -ForegroundColor Yellow
Write-Host "Copying configuration files to automation container..." -ForegroundColor Yellow

docker cp configure_gobgp.py clab-$LAB_NAME-automation:/workspace/
docker cp config_playbook.yml clab-$LAB_NAME-automation:/workspace/
docker cp inventory.yml clab-$LAB_NAME-automation:/workspace/
docker cp prepare_frr_user.sh clab-$LAB_NAME-automation:/workspace/

docker exec clab-$LAB_NAME-automation mkdir -p /root/.ssh

docker exec clab-$LAB_NAME-automation sh -c "ssh-keyscan 10.1.1.11 >> /root/.ssh/known_hosts"
docker exec clab-$LAB_NAME-automation chmod +x /workspace/prepare_frr_user.sh

Write-Host "[OK] Files copied" -ForegroundColor Green

# Final status
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Infrastructure Setup Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Lab Status:" -ForegroundColor Green
Write-Host "  - Management Network: 10.1.1.0/24"
Write-Host "  - Automation:  10.1.1.10 (tools ready)"
Write-Host "  - FRR1:        10.1.1.11 (SSH enabled)"
Write-Host "  - GoBGP1:      10.1.1.12 (gRPC API ready)"
Write-Host "  - Data Plane:  frr1:10.0.1.2 to gobgp1:10.0.1.3"
Write-Host ""
Write-Host "Next Step - Configure BGP:" -ForegroundColor Yellow
Write-Host "  docker exec -it clab-$LAB_NAME-automation bash"
Write-Host "  cd /workspace"
Write-Host "  ansible-playbook -i inventory.yml config_playbook.yml"
Write-Host ""