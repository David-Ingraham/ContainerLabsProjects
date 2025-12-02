#!/bin/bash
# Complete lab setup: build image, deploy containers, configure infrastructure

set -e

PROJECT_DIR="/Users/davidingraham/Desktop/personal_projects/networkAutomation/ContainerLabsProjects/ansible-bgp-containerlab"
IMAGE_NAME="network-automation:latest"
LAB_NAME="bgp-lab"

cd "$PROJECT_DIR"

echo "=========================================="
echo "BGP Lab Infrastructure Setup"
echo "=========================================="

# Step 1: Check if custom image exists, build if needed
echo ""
echo "=== Step 1: Docker Image ==="
if docker images | grep -q "network-automation.*latest"; then
    echo "✓ Image $IMAGE_NAME already exists"
else
    echo "Building $IMAGE_NAME (one-time operation)..."
    docker build -f Dockerfile.automation -t $IMAGE_NAME .
    echo "✓ Image built successfully"
fi

# Step 2: Deploy lab (destroy if running to ensure latest topology)
echo ""
echo "=== Step 2: Lab Deployment ==="
if docker ps | grep -q "clab-$LAB_NAME"; then
    echo "Existing lab detected - destroying to ensure latest topology..."
    docker run --rm -it --privileged \
      --network host \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v $(pwd):/lab \
      -w /lab \
      ghcr.io/srl-labs/clab containerlab destroy -t topology.yml --cleanup
    echo "✓ Old lab destroyed"
fi

echo "Deploying fresh lab..."
docker run --rm -it --privileged \
  --network host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd):/lab \
  -w /lab \
  ghcr.io/srl-labs/clab containerlab deploy -t topology.yml
echo "✓ Lab deployed"

# Step 3: Wait for containers to stabilize
echo ""
echo "=== Step 3: Container Stabilization ==="
echo "Waiting for containers to be ready..."
sleep 5
echo "✓ Containers ready"


# Step 4: Configure data plane interfaces
echo ""
echo "=== Step 4: Data Plane Configuration ==="
echo "Configuring interface IPs on eth1..."
chmod +x create-links.sh
./create-links.sh
echo "✓ Data plane configured"


# enabling ip forwarding in kernel of gobgp1
docker run --rm \
  --network container:clab-bgp-lab-gobgp1 \
  --privileged \
  alpine sh -c "sysctl -w net.ipv4.ip_forward=1 && ip route add 10.1.0.0/24 via 10.0.1.2"


# Step 5: Copy configuration files to automation container
echo ""
echo "=== Step 5: Configuration Files ==="
echo "Copying files to automation container..."
docker exec clab-$LAB_NAME-automation mkdir -p /workspace 2>/dev/null || true

docker cp configure_gobgp.py clab-$LAB_NAME-automation:/workspace/
docker cp config_playbook.yml clab-$LAB_NAME-automation:/workspace/
docker cp inventory.yml clab-$LAB_NAME-automation:/workspace/
docker cp prepare_frr_user.sh clab-$LAB_NAME-automation:/workspace/
docker exec clab-$LAB_NAME-automation chmod +x /workspace/prepare_frr_user.sh

#docker exec clab-$LAB_NAME-automation mkdir -p /root/.ssh

#docker exec clab-$LAB_NAME-automation sh -c "ssh-keyscan 10.1.1.11 >> /root/.ssh/known_hosts"

echo "✓ Files copied"

# Final status
echo ""
echo "=========================================="
echo "Infrastructure Setup Complete!"
echo "=========================================="
echo ""
echo "Lab Status:"
echo "  • Management Network: 10.1.1.0/24"
echo "    - Automation:  10.1.1.10"
echo "    - FRR1:        10.1.1.11"
echo "    - GoBGP1:      10.1.1.12"
echo "    - Host1:       10.1.1.20"
echo "    - Host2:       10.1.1.21"
echo ""
echo "  • BGP Data Plane: 10.0.1.0/29"
echo "    - FRR1 <-> GoBGP1"
echo ""
echo "  • Backend Networks:"
echo "    - FRR1 backend:   10.1.0.0/24 (FRR: 10.1.0.2, host1: 10.1.0.10)"
echo "    - GoBGP1 backend: 10.2.0.0/24 (GoBGP: 10.2.0.2, host2: 10.2.0.10)"
echo ""
echo "Configure BGP:"
echo "  docker exec -it clab-$LAB_NAME-automation ansible-playbook -i inventory.yml config_playbook.yml"


