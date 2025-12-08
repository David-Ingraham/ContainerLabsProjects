# Start multicast source on host1
# Sends UDP packets to multicast group 239.1.1.1

$LAB_NAME = "bgp-lab"
$SOURCE_HOST = "clab-$LAB_NAME-host1"
$MCAST_GROUP = "239.1.1.1"
$MCAST_PORT = "5000"
$MESSAGE = "Multicast test from host1"

Write-Host "============================================"
Write-Host "Multicast Source Test"
Write-Host "============================================"
Write-Host "Host:          $SOURCE_HOST"
Write-Host "Group:         $MCAST_GROUP"
Write-Host "Port:          $MCAST_PORT"
Write-Host "============================================"

# Check if container exists
$containerCheck = docker inspect "$SOURCE_HOST" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Container $SOURCE_HOST not found"
    exit 1
}

Write-Host ""
Write-Host "Starting multicast sender (Ctrl+C to stop)..."
Write-Host "Sending: $MESSAGE"
Write-Host ""

# Python script for multicast sender
$pythonScript = @"
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
    print('\nStopped')
finally:
    sock.close()
"@

docker exec -it "$SOURCE_HOST" python3 -c $pythonScript
