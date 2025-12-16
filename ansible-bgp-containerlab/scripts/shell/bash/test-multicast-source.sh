#!/bin/bash


# Start multicast source on host1
# Sends UDP packets to multicast group 239.1.1.1

# Parse arguments
DESIGN="${1:-og}"  # Default to "og" if no argument provided

# Script is in scripts/shell/bash/, project root is 3 levels up
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
INVENTORY_FILE="$PROJECT_DIR/ansible/inventories/inventory-$DESIGN.yml"

# Extract lab_name from inventory file
LAB_NAME=$(grep -E '^\s*lab_name:' "$INVENTORY_FILE" | awk '{print $2}')
if [ -z "$LAB_NAME" ]; then
    echo "ERROR: Could not extract lab_name from $INVENTORY_FILE"
    exit 1
fi

SOURCE_HOST="clab-${LAB_NAME}-host1"
MCAST_GROUP="239.1.1.1"
MCAST_PORT="5000"
MESSAGE="Multicast test from host1"

echo "============================================"
echo "Multicast Source Test"
echo "============================================"
echo "Host:          $SOURCE_HOST"
echo "Group:         $MCAST_GROUP"
echo "Port:          $MCAST_PORT"
echo "============================================"

# Check if container exists
if ! docker inspect "$SOURCE_HOST" >/dev/null 2>&1; then
    echo "[ERROR] Container $SOURCE_HOST not found"
    exit 1
fi

echo ""
echo "Starting multicast sender (Ctrl+C to stop)..."
echo "Sending: $MESSAGE"
echo ""

# Use Python to send multicast packets
docker exec -it "$SOURCE_HOST" python3 -c "
import socket
import struct
import time

MCAST_GRP = '$MCAST_GROUP'
MCAST_PORT = $MCAST_PORT
MESSAGE = b'$MESSAGE'

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 32)

print(f'Sending to {MCAST_GRP}:{MCAST_PORT}')
counter = 0
try:
    while True:
        msg = MESSAGE + b' - packet ' + str(counter).encode()
        sock.sendto(msg, (MCAST_GRP, MCAST_PORT))
        print(f'Sent packet {counter}: {msg.decode()}')
        counter += 1
        time.sleep(2)
except KeyboardInterrupt:
    print('\\nStopped')
finally:
    sock.close()
"

