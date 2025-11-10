#!/bin/bash
# Script to manually create network links between containers
# This works around containerlab's race condition on macOS Docker

set -x  # Exit on any error

echo "Creating network links between containers..."

# Function to create a link between two containers
# Args: $1=container1_name, $2=container1_interface, $3=container2_name, $4=container2_interface
create_link() {
    local c1_name="$1"
    local c1_iface="$2"
    local c2_name="$3"
    local c2_iface="$4"
    
    echo "Creating link: $c1_name:$c1_iface <--> $c2_name:$c2_iface"
    
    # Get container PIDs (Process IDs)
    # Docker containers run as processes on the host
    # We need the PID to access the container's network namespace
    local c1_pid=$(docker inspect -f '{{.State.Pid}}' "$c1_name")
    local c2_pid=$(docker inspect -f '{{.State.Pid}}' "$c2_name")
    
    if [ -z "$c1_pid" ] || [ "$c1_pid" = "0" ]; then
        echo "ERROR: Container $c1_name not running"
        return 1
    fi
    
    if [ -z "$c2_pid" ] || [ "$c2_pid" = "0" ]; then
        echo "ERROR: Container $c2_name not running"
        return 1
    fi
    
    # Create unique veth pair names (max 15 chars for Linux)
    # veth pairs are virtual ethernet devices that act like a cable
    # Data sent to one end comes out the other end
    local veth_a="v${c1_name: -3}${c2_name: -3}a"
    local veth_b="v${c1_name: -3}${c2_name: -3}b"
    
    # Step 1: Create veth pair in host network namespace
    # This creates two virtual interfaces connected to each other
    echo "  Creating veth pair: $veth_a <-> $veth_b"
    ip link add "$veth_a" type veth peer name "$veth_b"
    
    # Step 2: Move one end into container1's network namespace
    # Each container has its own isolated network namespace
    # We access it via /proc/<PID>/ns/net
    echo "  Moving $veth_a into $c1_name namespace"
    ip link set "$veth_a" netns "$c1_pid"
    
    # Step 3: Move other end into container2's network namespace
    echo "  Moving $veth_b into $c2_name namespace"
    ip link set "$veth_b" netns "$c2_pid"
    
    # Step 4: Rename interfaces inside containers to match topology
    # We use nsenter to execute commands inside a container's namespace
    # nsenter -t <PID> -n runs a command in that PID's network namespace
    echo "  Renaming $veth_a to $c1_iface in $c1_name"
    nsenter -t "$c1_pid" -n ip link set "$veth_a" name "$c1_iface"
    
    echo "  Renaming $veth_b to $c2_iface in $c2_name"
    nsenter -t "$c2_pid" -n ip link set "$veth_b" name "$c2_iface"
    
    # Step 5: Bring up both interfaces
    # Interfaces start in DOWN state, we need to enable them
    echo "  Bringing up $c1_iface in $c1_name"
    nsenter -t "$c1_pid" -n ip link set "$c1_iface" up
    
    echo "  Bringing up $c2_iface in $c2_name"
    nsenter -t "$c2_pid" -n ip link set "$c2_iface" up
    
    echo "  Link created successfully!"
}

# Define container names (use full names from containerlab)
CLIENT1="clab-multi-vendor-api-bgp-client1"
FRR1="clab-multi-vendor-api-bgp-frr1"
GOBGP1="clab-multi-vendor-api-bgp-gobgp1"
CLIENT2="clab-multi-vendor-api-bgp-client2"

# Create the three links according to topology:
# client1 <--> frr1 <--> gobgp1 <--> client2

echo ""
echo "Link 1 of 3:"
create_link "$CLIENT1" "eth1" "$FRR1" "eth1"

echo ""
echo "Link 2 of 3:"
create_link "$FRR1" "eth2" "$GOBGP1" "eth1"

echo ""
echo "Link 3 of 3:"
create_link "$GOBGP1" "eth2" "$CLIENT2" "eth1"

echo ""
echo "All links created successfully!"
echo ""
echo "Verify with: docker exec $CLIENT1 ip addr"

