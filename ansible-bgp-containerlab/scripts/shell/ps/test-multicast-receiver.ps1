# Join multicast group and receive packets on receiver containers

param(
    [string]$Design = "og",
    [string]$ReceiverName = "receiver1"
)

$SCRIPT_DIR = $PSScriptRoot
$PROJECT_DIR = (Get-Item $SCRIPT_DIR).Parent.Parent.Parent.FullName
$INVENTORY_FILE = Join-Path $PROJECT_DIR "ansible/inventories/inventory-$Design.yml"

# Extract lab_name from inventory file
$LAB_NAME = (Get-Content $INVENTORY_FILE | Select-String "^\s*lab_name:" | ForEach-Object { ($_ -split ':')[1].Trim() })
if (-not $LAB_NAME) {
    Write-Host "ERROR: Could not extract lab_name from $INVENTORY_FILE" -ForegroundColor Red
    exit 1
}

$MCAST_GROUP = "239.1.1.1"
$MCAST_PORT = "5000"
$RECEIVER_HOST = "clab-$LAB_NAME-$ReceiverName"

Write-Host "============================================"
Write-Host "Multicast Receiver Test"
Write-Host "============================================"
Write-Host "Host:          $RECEIVER_HOST"
Write-Host "Group:         $MCAST_GROUP"
Write-Host "Port:          $MCAST_PORT"
Write-Host "============================================"

# Check if container exists
$containerCheck = docker inspect "$RECEIVER_HOST" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Container $RECEIVER_HOST not found"
    Write-Host "Usage: .\test-multicast-receiver.ps1 [design] [receiver_name]"
    Write-Host "Example: .\test-multicast-receiver.ps1 linear receiver1"
    exit 1
}

Write-Host ""
Write-Host "Joining multicast group (Ctrl+C to stop)..."
Write-Host ""

# Python script for multicast receiver
$pythonScript = @"
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
    print('\nStopped')
finally:
    sock.close() 
"@

docker exec -it "$RECEIVER_HOST" python3 -c $pythonScript
