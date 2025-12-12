# Complete lab setup: build image, deploy containers, configure infrastructure

param(
    [string]$Design = "og"
)

$ErrorActionPreference = "Stop"

# Script is in scripts/shell/, project root is 2 levels up
$SCRIPT_DIR = $PSScriptRoot
$PROJECT_DIR = (Get-Item $SCRIPT_DIR).Parent.Parent.Parent.FullName

$AUTOMATION_IMAGE = "network-automation:latest"
$FRR_IMAGE = "frr-ansible:latest"
$LAB_NAME = "bgp-lab"
$TOPOLOGY_FILE = "containerlab/topologies/topology-$Design.yml"
$INVENTORY_FILE = "ansible/inventories/inventory-$Design.yml"

# Directory structure
$DOCKER_DIR = Join-Path $PROJECT_DIR "docker"
$ANSIBLE_DIR = Join-Path $PROJECT_DIR "ansible"
$CONTAINERLAB_DIR = Join-Path $PROJECT_DIR "containerlab"
$SCRIPTS_PYTHON_DIR = Join-Path $PROJECT_DIR "scripts/python"
$CREDENTIALS_DIR = Join-Path $ANSIBLE_DIR "credentials"
$PLAYBOOKS_DIR = Join-Path $ANSIBLE_DIR "playbooks"

Set-Location $PROJECT_DIR

# Source credentials from env file
$credentialsFile = Join-Path $CREDENTIALS_DIR "credentials.env"
if (Test-Path $credentialsFile) {
    Get-Content $credentialsFile | ForEach-Object {
        if ($_ -match "^\s*([^#][^=]+)=(.*)$") {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            Set-Variable -Name $name -Value $value -Scope Script
        }
    }
} else {
    Write-Host "ERROR: credentials.env not found at $credentialsFile" -ForegroundColor Red
    Write-Host "Create ansible/credentials/credentials.env with FRR_ROOT_PASS, FRR_USER, FRR_PASS"
    exit 1
}

# Generate credentials.yml for Ansible from env vars
$credentialsYml = @"
# Ansible credentials for FRR routers
# Auto-generated from credentials.env - do not edit directly
ansible_user: $FRR_USER
ansible_password: $FRR_PASS
"@
Set-Content -Path (Join-Path $CREDENTIALS_DIR "credentials.yml") -Value $credentialsYml

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
    docker build -f "$DOCKER_DIR/Dockerfile.automation" -t $AUTOMATION_IMAGE $PROJECT_DIR
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
    docker build -f "$DOCKER_DIR/Dockerfile.frr" -t $FRR_IMAGE `
        --build-arg FRR_ROOT_PASS="$FRR_ROOT_PASS" `
        --build-arg FRR_USER="$FRR_USER" `
        --build-arg FRR_PASS="$FRR_PASS" $PROJECT_DIR
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Image $FRR_IMAGE built" -ForegroundColor Green
    } else {
        throw "Failed to build FRR Docker image"
    }
}

# Step 2: Remove all containers and networks
Write-Host ""
Write-Host "=== Step 2: Cleanup ===" -ForegroundColor Yellow

# Stop running containers
$allContainers = docker ps -q
if ($allContainers) {
    docker kill $allContainers 2>$null
}

# Remove all containers
$allContainersIncludingStopped = docker ps -aq
if ($allContainersIncludingStopped) {
    docker rm -f $allContainersIncludingStopped 2>$null
}
Write-Host "Containers removed" -ForegroundColor Green

# Remove non-default networks
docker network ls --format "{{.Name}}" | Where-Object { $_ -notin @("bridge", "host", "none") } | ForEach-Object {
    docker network rm $_ 2>$null
}
Write-Host "Networks removed" -ForegroundColor Green

# Remove containerlab state files
if (Test-Path "clab-$LAB_NAME") {
    Remove-Item -Recurse -Force "clab-$LAB_NAME" 2>$null
}

Write-Host "Cleanup complete" -ForegroundColor Green

Write-Host "Deploying fresh lab..." -ForegroundColor Yellow
Write-Host "Using topology: $TOPOLOGY_FILE" -ForegroundColor Cyan
docker run --rm -it --privileged `
  --network host `
  -v /var/run/docker.sock:/var/run/docker.sock `
  -v ${PROJECT_DIR}:/lab `
  -w /lab `
  ghcr.io/srl-labs/clab containerlab deploy -t $TOPOLOGY_FILE --reconfigure

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

# Data-driven approach: read network config from inventory.yml
python "$SCRIPTS_PYTHON_DIR/create_links.py" -d $Design

if ($LASTEXITCODE -eq 0) {
    Write-Host "Data plane configured" -ForegroundColor Green
} else {
    Write-Host "Warning: Data plane configuration had issues, but continuing..." -ForegroundColor Yellow
}

# Enable IP forwarding and add static routes on gobgp1
# GoBGP image has no shell, so we use Alpine in gobgp1's network namespace
# GoBGP only does BGP protocol - it doesn't install routes into kernel
# Static routes required for kernel to forward packets
Write-Host "Configuring gobgp1 kernel routing..." -ForegroundColor Yellow
docker run --rm `
  --network container:clab-bgp-lab-gobgp1 `
  --privileged `
  alpine sh -c "sysctl -w net.ipv4.ip_forward=1 && ip route add 10.1.0.0/24 via 10.0.1.2 && ip route add 10.2.0.0/24 via 10.0.1.2"
Write-Host "IP forwarding and routes configured on gobgp1" -ForegroundColor Green

# Step 5: Copy configuration files to automation container
Write-Host ""
Write-Host "=== Step 5: Configuration Files ===" -ForegroundColor Yellow
Write-Host "Copying files to automation container..." -ForegroundColor Yellow

docker exec clab-$LAB_NAME-automation mkdir -p /workspace 2>$null

docker cp "$SCRIPTS_PYTHON_DIR/configure_gobgp.py" clab-$LAB_NAME-automation:/workspace/
docker cp "$PLAYBOOKS_DIR/config_playbook.yml" clab-$LAB_NAME-automation:/workspace/
docker cp "$INVENTORY_FILE" clab-$LAB_NAME-automation:/workspace/inventory.yml
docker cp "$CREDENTIALS_DIR/credentials.yml" clab-$LAB_NAME-automation:/workspace/

Write-Host "Files copied" -ForegroundColor Green

# Final status
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Infrastructure Setup Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Topology:" -ForegroundColor Green
Write-Host ""
Write-Host "                     [frr2] -------- [receiver1, receiver2]"
Write-Host "                       |               10.2.0.0/24"
Write-Host "                    10.1.0.3"
Write-Host "                       |"
Write-Host "  host1 (10.1.0.10) -- frr1 (10.1.0.2) -- gobgp1 -- host2"
Write-Host "                            10.0.1.x        10.3.0.0/24"
Write-Host ""
Write-Host "Management Network: 10.1.1.0/24" -ForegroundColor Green
Write-Host "  - Automation:  10.1.1.10"
Write-Host "  - FRR1:        10.1.1.11 (AS 65001) - BGP + Multicast FHR"
Write-Host "  - FRR2:        10.1.1.12 (AS 65003) - Multicast LHR"
Write-Host "  - GoBGP1:      10.1.1.13 (AS 65002) - BGP peer"
Write-Host "  - Host1:       10.1.1.20 (multicast source)"
Write-Host "  - Host2:       10.1.1.21"
Write-Host "  - Receiver1:   10.1.1.22"
Write-Host "  - Receiver2:   10.1.1.23"
Write-Host ""
Write-Host "Data Plane Networks:" -ForegroundColor Green
Write-Host "  - frr1-network:  10.1.0.0/24 (frr1: .2, frr2: .3, host1: .10)"
Write-Host "  - frr2-network:  10.2.0.0/24 (frr2: .2, receiver1: .10, receiver2: .20)"
Write-Host "  - gobgp-network: 10.3.0.0/24 (gobgp1: .2, host2: .10)"
Write-Host "  - link-frr1-gobgp1: 10.0.1.0/29 (frr1: .2, gobgp1: .3)"
Write-Host ""
Write-Host "Configure BGP:" -ForegroundColor Yellow
Write-Host "  docker exec -it clab-$LAB_NAME-automation ansible-playbook -i inventory.yml config_playbook.yml"

