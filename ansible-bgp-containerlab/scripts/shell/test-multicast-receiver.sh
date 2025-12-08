#!/bin/bash
# Join multicast group and receive packets on receiver containers

LAB_NAME="bgp-lab"
MCAST_GROUP="239.1.1.1"
MCAST_PORT="5000"

# Check which receiver to use
RECEIVER_NAME="${1:-receiver1}"
RECEIVER_HOST="clab-${LAB_NAME}-${RECEIVER_NAME}"

echo "============================================"
echo "Multicast Receiver Test"
echo "============================================"
echo "Host:          $RECEIVER_HOST"
echo "Group:         $MCAST_GROUP"
echo "Port:          $MCAST_PORT"
echo "============================================"

# Check if container exists
if ! docker inspect "$RECEIVER_HOST" >/dev/null 2>&1; then
    echo "[ERROR] Container $RECEIVER_HOST not found"
    echo "Usage: $0 [receiver1|receiver2]"
    exit 1
fi

echo ""
echo "Joining multicast group (Ctrl+C to stop)..."
echo ""

# Use Python to receive multicast packets
docker exec -it "$RECEIVER_HOST" python3 -c "
import socket
import struct

MCAST_GRP = '$MCAST_GROUP'
MCAST_PORT = $MCAST_PORT

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(('', MCAST_PORT))

# Join multicast group
mreq = struct.pack('4sl', socket.inet_aton(MCAST_GRP), socket.INADDR_ANY)
sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

print(f'Listening on {MCAST_GRP}:{MCAST_PORT}')
print('Waiting for packets...')
print()

try:
    while True:
        data, addr = sock.recvfrom(1024)
        print(f'Received from {addr[0]}: {data.decode()}')
except KeyboardInterrupt:
    print('\\nStopped')
finally:
    sock.close()
"
