#!/bin/bash
# Complete lab setup: build image, deploy containers, configure infrastructure

set -e

# Script is in scripts/shell/, project root is 2 levels up
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

AUTOMATION_IMAGE="network-automation:latest"
FRR_IMAGE="frr-ansible:latest"
LAB_NAME="bgp-lab"

# Directory structure
DOCKER_DIR="$PROJECT_DIR/docker"
ANSIBLE_DIR="$PROJECT_DIR/ansible"
CONTAINERLAB_DIR="$PROJECT_DIR/containerlab"
SCRIPTS_PYTHON_DIR="$PROJECT_DIR/scripts/python"
CREDENTIALS_DIR="$ANSIBLE_DIR/credentials"
PLAYBOOKS_DIR="$ANSIBLE_DIR/playbooks"

cd "$PROJECT_DIR"

# Source credentials from env file
if [ -f "$CREDENTIALS_DIR/credentials.env" ]; then
    source "$CREDENTIALS_DIR/credentials.env"
else
    echo "ERROR: credentials.env not found at $CREDENTIALS_DIR/credentials.env"
    echo "Create ansible/credentials/credentials.env with FRR_ROOT_PASS, FRR_USER, FRR_PASS"
    exit 1
fi

# Generate credentials.yml for Ansible from env vars
cat > "$CREDENTIALS_DIR/credentials.yml" << EOF
# Ansible credentials for FRR routers
# Auto-generated from credentials.env - do not edit directly
ansible_user: ${FRR_USER}
ansible_password: ${FRR_PASS}
EOF

echo "=========================================="
echo "BGP Lab Infrastructure Setup"
echo "=========================================="

# Step 1: Check if custom images exist, build if needed
echo ""
echo "=== Step 1: Docker Images ==="

# Automation container image
if docker images | grep -q "network-automation.*latest"; then
    echo "Image $AUTOMATION_IMAGE exists"
else
    echo "Building $AUTOMATION_IMAGE..."
    docker build -f "$DOCKER_DIR/Dockerfile.automation" -t $AUTOMATION_IMAGE "$PROJECT_DIR"
    echo "Image $AUTOMATION_IMAGE built"
fi

# FRR container image (with credentials from env)
if docker images | grep -q "frr-ansible.*latest"; then
    echo "Image $FRR_IMAGE exists"
else
    echo "Building $FRR_IMAGE..."
    docker build -f "$DOCKER_DIR/Dockerfile.frr" -t $FRR_IMAGE \
        --build-arg FRR_ROOT_PASS="$FRR_ROOT_PASS" \
        --build-arg FRR_USER="$FRR_USER" \
        --build-arg FRR_PASS="$FRR_PASS" "$PROJECT_DIR"
    echo "Image $FRR_IMAGE built"
fi

# Step 2: Remove all containers and networks
echo ""
echo "=== Step 2: Cleanup ==="

# Stop running containers
docker kill $(docker ps -q) 2>/dev/null || true

# Remove all containers
docker rm -f $(docker ps -aq) 2>/dev/null || true
echo "Containers removed"

# Remove non-default networks
docker network ls --format "{{.Name}}" | grep -v -E "^(bridge|host|none)$" | xargs -r docker network rm 2>/dev/null || true
echo "Networks removed"

# Remove containerlab state files
rm -rf "clab-$LAB_NAME" 2>/dev/null || true

echo "Cleanup complete"

echo "Deploying fresh lab..."
docker run --rm -it --privileged \
  --network host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PROJECT_DIR":/lab \
  -w /lab \
  ghcr.io/srl-labs/clab containerlab deploy -t containerlab/topology.yml --reconfigure
echo "Lab deployed"

# Step 3: Wait for containers to stabilize
echo ""
echo "=== Step 3: Container Stabilization ==="
echo "Waiting for containers to be ready..."
sleep 5
echo "Containers ready"

# Step 4: Configure data plane interfaces
echo ""
echo "=== Step 4: Data Plane Configuration ==="
echo "Configuring data plane networks from inventory.yml..."

# Data-driven approach: read network config from inventory.yml
python3 "$SCRIPTS_PYTHON_DIR/create_links.py"

echo "Data plane configured"

# Enable IP forwarding and add static routes on gobgp1
# GoBGP image has no shell, so we use Alpine in gobgp1's network namespace
# GoBGP only does BGP protocol - it doesn't install routes into kernel
echo "Configuring gobgp1 kernel routing..."
docker run --rm \
  --network container:clab-bgp-lab-gobgp1 \
  --privileged \
  alpine sh -c "sysctl -w net.ipv4.ip_forward=1 && ip route add 10.1.0.0/24 via 10.0.1.2 && ip route add 10.2.0.0/24 via 10.0.1.2"
echo "IP forwarding and routes configured on gobgp1"

# Step 5: Copy configuration files to automation container
echo ""
echo "=== Step 5: Configuration Files ==="
echo "Copying files to automation container..."
docker exec clab-$LAB_NAME-automation mkdir -p /workspace 2>/dev/null || true

docker cp "$SCRIPTS_PYTHON_DIR/configure_gobgp.py" clab-$LAB_NAME-automation:/workspace/
docker cp "$PLAYBOOKS_DIR/config_playbook.yml" clab-$LAB_NAME-automation:/workspace/
docker cp "$ANSIBLE_DIR/inventory.yml" clab-$LAB_NAME-automation:/workspace/
docker cp "$CREDENTIALS_DIR/credentials.yml" clab-$LAB_NAME-automation:/workspace/

echo "Files copied"

# Final status
echo ""
echo "=========================================="
echo "Infrastructure Setup Complete!"
echo "=========================================="
echo ""
echo "Topology:"
echo ""
echo "                     [frr2] -------- [receiver1, receiver2]"
echo "                       |               10.2.0.0/24"
echo "                    10.1.0.3"
echo "                       |"
echo "  host1 (10.1.0.10) -- frr1 (10.1.0.2) -- gobgp1 -- host2"
echo "                            10.0.1.x        10.3.0.0/24"
echo ""
echo "Management Network: 10.1.1.0/24"
echo "  - Automation:  10.1.1.10"
echo "  - FRR1:        10.1.1.11 (AS 65001) - BGP + Multicast FHR"
echo "  - FRR2:        10.1.1.12 (AS 65003) - Multicast LHR"
echo "  - GoBGP1:      10.1.1.13 (AS 65002) - BGP peer"
echo "  - Host1:       10.1.1.20 (multicast source)"
echo "  - Host2:       10.1.1.21"
echo "  - Receiver1:   10.1.1.22"
echo "  - Receiver2:   10.1.1.23"
echo ""
echo "Data Plane Networks:"
echo "  - frr1-network:  10.1.0.0/24 (frr1: .2, frr2: .3, host1: .10)"
echo "  - frr2-network:  10.2.0.0/24 (frr2: .2, receiver1: .10, receiver2: .20)"
echo "  - gobgp-network: 10.3.0.0/24 (gobgp1: .2, host2: .10)"
echo "  - link-frr1-gobgp1: 10.0.1.0/29 (frr1: .2, gobgp1: .3)"
echo ""
echo "Configure BGP:"
echo "  docker exec -it clab-$LAB_NAME-automation ansible-playbook -i inventory.yml config_playbook.yml"
