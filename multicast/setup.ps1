# SR Linux Multicast Lab Setup Script (Windows PowerShell)
# Deploys containerlab topology and configures data plane networks

$ErrorActionPreference = "Stop"

$PROJECT_DIR = $PSScriptRoot
$AUTOMATION_IMAGE = "srlinux-automation:latest"
$LAB_NAME = "srlinux-multicast-lab"

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
    exit 1
}

# Generate credentials.yml for Ansible
$credentialsYml = @"
# SR Linux credentials for Ansible
# Auto-generated from credentials.env
ansible_user: $SRLINUX_USER
ansible_password: $SRLINUX_PASS
"@
Set-Content -Path (Join-Path $PROJECT_DIR "credentials.yml") -Value $credentialsYml

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SR Linux Multicast Lab Setup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Step 1: Pull SR Linux image
Write-Host ""
Write-Host "=== Step 1: Pull SR Linux Image ===" -ForegroundColor Yellow
$srlExists = docker images --format "{{.Repository}}:{{.Tag}}" | Select-String "ghcr.io/nokia/srlinux"
if (-not $srlExists) {
    Write-Host "Pulling Nokia SR Linux image..." -ForegroundColor Yellow
    docker pull ghcr.io/nokia/srlinux:latest
}
Write-Host "SR Linux image ready" -ForegroundColor Green

# Step 2: Build automation container
Write-Host ""
Write-Host "=== Step 2: Build Automation Image ===" -ForegroundColor Yellow
$automationExists = docker images --format "{{.Repository}}:{{.Tag}}" | Select-String "srlinux-automation:latest"
if (-not $automationExists) {
    Write-Host "Building automation image..." -ForegroundColor Yellow
    docker build -f Dockerfile.automation -t $AUTOMATION_IMAGE .
}
Write-Host "Automation image ready" -ForegroundColor Green

# Step 3: Create startup config directory
Write-Host ""
Write-Host "=== Step 3: Create Config Directory ===" -ForegroundColor Yellow
$configDir = Join-Path $PROJECT_DIR "configs"
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir | Out-Null
}
# Create minimal startup configs (SR Linux will generate defaults)
@"
# srl1 startup config
# Basic configuration - full config via Ansible
"@ | Set-Content (Join-Path $configDir "srl1.cfg")

@"
# srl2 startup config
"@ | Set-Content (Join-Path $configDir "srl2.cfg")

@"
# srl3 startup config
"@ | Set-Content (Join-Path $configDir "srl3.cfg")

Write-Host "Config directory ready" -ForegroundColor Green

# Step 4: Deploy lab
Write-Host ""
Write-Host "=== Step 4: Deploy Lab ===" -ForegroundColor Yellow
$labRunning = docker ps --format "{{.Names}}" | Select-String "clab-$LAB_NAME"
if ($labRunning) {
    Write-Host "Destroying existing lab..." -ForegroundColor Yellow
    docker run --rm -it --privileged `
        -v /var/run/docker.sock:/var/run/docker.sock `
        -v ${PWD}:/lab `
        -w /lab `
        ghcr.io/srl-labs/clab containerlab destroy -t topology.yml --cleanup
}

Write-Host "Deploying lab..." -ForegroundColor Yellow
docker run --rm -it --privileged `
    -v /var/run/docker.sock:/var/run/docker.sock `
    -v ${PWD}:/lab `
    -w /lab `
    ghcr.io/srl-labs/clab containerlab deploy -t topology.yml

Write-Host "Lab deployed" -ForegroundColor Green

# Step 5: Wait for SR Linux to boot
Write-Host ""
Write-Host "=== Step 5: Wait for SR Linux Boot ===" -ForegroundColor Yellow
Write-Host "SR Linux takes 60-90 seconds to fully boot..." -ForegroundColor Yellow
Start-Sleep -Seconds 30
Write-Host "Waiting for management interfaces..." -ForegroundColor Yellow
Start-Sleep -Seconds 30
Write-Host "SR Linux should be ready" -ForegroundColor Green

# Step 6: Configure data plane networks
Write-Host ""
Write-Host "=== Step 6: Data Plane Configuration ===" -ForegroundColor Yellow
python create_links.py
Write-Host "Data plane configured" -ForegroundColor Green

# Step 7: Copy files to automation container
Write-Host ""
Write-Host "=== Step 7: Setup Automation Container ===" -ForegroundColor Yellow
docker exec clab-$LAB_NAME-automation mkdir -p /workspace 2>$null

docker cp inventory.yml clab-$LAB_NAME-automation:/workspace/
docker cp credentials.yml clab-$LAB_NAME-automation:/workspace/
docker cp configure_srlinux.py clab-$LAB_NAME-automation:/workspace/

Write-Host "Files copied to automation container" -ForegroundColor Green

# Final status
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Lab Setup Complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Management Network: 172.20.0.0/24" -ForegroundColor Green
Write-Host "  srl1:       172.20.0.11"
Write-Host "  srl2:       172.20.0.12"
Write-Host "  srl3:       172.20.0.13"
Write-Host "  automation: 172.20.0.10"
Write-Host ""
Write-Host "SR Linux APIs:" -ForegroundColor Green
Write-Host "  JSON-RPC: http://172.20.0.11 (admin/NokiaSrl1!)"
Write-Host "  gNMI:     172.20.0.11:57400"
Write-Host ""
Write-Host "Test JSON-RPC API:" -ForegroundColor Yellow
Write-Host "  docker exec -it clab-$LAB_NAME-automation python /workspace/configure_srlinux.py"
Write-Host ""
Write-Host "Access SR Linux CLI:" -ForegroundColor Yellow
Write-Host "  docker exec -it clab-$LAB_NAME-srl1 sr_cli"

