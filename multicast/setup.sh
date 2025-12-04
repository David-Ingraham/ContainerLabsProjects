#!/bin/bash
# SR Linux Multicast Lab Setup Script (Linux/macOS)
# Deploys containerlab topology and configures data plane networks

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOMATION_IMAGE="srlinux-automation:latest"
LAB_NAME="srlinux-multicast-lab"

cd "$PROJECT_DIR"

# Source credentials from env file
if [ -f credentials.env ]; then
    source credentials.env
else
    echo "ERROR: credentials.env not found"
    exit 1
fi

# Generate credentials.yml for Ansible
cat > credentials.yml << EOF
# SR Linux credentials for Ansible
# Auto-generated from credentials.env
ansible_user: ${SRLINUX_USER}
ansible_password: ${SRLINUX_PASS}
EOF

echo "=========================================="
echo "SR Linux Multicast Lab Setup"
echo "=========================================="

# Step 1: Pull SR Linux image
echo ""
echo "=== Step 1: Pull SR Linux Image ==="
if ! docker images | grep -q "ghcr.io/nokia/srlinux"; then
    echo "Pulling Nokia SR Linux image..."
    docker pull ghcr.io/nokia/srlinux:latest
fi
echo "SR Linux image ready"

# Step 2: Build automation container
echo ""
echo "=== Step 2: Build Automation Image ==="
if ! docker images | grep -q "srlinux-automation.*latest"; then
    echo "Building automation image..."
    docker build -f Dockerfile.automation -t $AUTOMATION_IMAGE .
fi
echo "Automation image ready"

# Step 3: Create startup config directory
echo ""
echo "=== Step 3: Create Config Directory ==="
mkdir -p configs
echo "# srl1 startup config" > configs/srl1.cfg
echo "# srl2 startup config" > configs/srl2.cfg
echo "# srl3 startup config" > configs/srl3.cfg
echo "Config directory ready"

# Step 4: Deploy lab
echo ""
echo "=== Step 4: Deploy Lab ==="
if docker ps | grep -q "clab-$LAB_NAME"; then
    echo "Destroying existing lab..."
    docker run --rm -it --privileged \
        --network host \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v $(pwd):/lab \
        -w /lab \
        ghcr.io/srl-labs/clab containerlab destroy -t topology.yml --cleanup
fi

echo "Deploying lab..."
docker run --rm -it --privileged \
    --network host \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v $(pwd):/lab \
    -w /lab \
    ghcr.io/srl-labs/clab containerlab deploy -t topology.yml

echo "Lab deployed"

# Step 5: Wait for SR Linux to boot
echo ""
echo "=== Step 5: Wait for SR Linux Boot ==="
echo "SR Linux takes 60-90 seconds to fully boot..."
sleep 30
echo "Waiting for management interfaces..."
sleep 30
echo "SR Linux should be ready"

# Step 6: Configure data plane networks
echo ""
echo "=== Step 6: Data Plane Configuration ==="
python3 create_links.py
echo "Data plane configured"

# Step 7: Copy files to automation container
echo ""
echo "=== Step 7: Setup Automation Container ==="
docker exec clab-$LAB_NAME-automation mkdir -p /workspace 2>/dev/null || true

docker cp inventory.yml clab-$LAB_NAME-automation:/workspace/
docker cp credentials.yml clab-$LAB_NAME-automation:/workspace/
docker cp configure_srlinux.py clab-$LAB_NAME-automation:/workspace/

echo "Files copied to automation container"

# Final status
echo ""
echo "=========================================="
echo "Lab Setup Complete"
echo "=========================================="
echo ""
echo "Management Network: 172.20.0.0/24"
echo "  srl1:       172.20.0.11"
echo "  srl2:       172.20.0.12"
echo "  srl3:       172.20.0.13"
echo "  automation: 172.20.0.10"
echo ""
echo "SR Linux APIs:"
echo "  JSON-RPC: http://172.20.0.11 (admin/NokiaSrl1!)"
echo "  gNMI:     172.20.0.11:57400"
echo ""
echo "Test JSON-RPC API:"
echo "  docker exec -it clab-$LAB_NAME-automation python /workspace/configure_srlinux.py"
echo ""
echo "Access SR Linux CLI:"
echo "  docker exec -it clab-$LAB_NAME-srl1 sr_cli"

