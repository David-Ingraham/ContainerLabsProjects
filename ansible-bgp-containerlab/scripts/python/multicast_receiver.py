import socket
import struct

MCAST_GRP = '239.1.1.1'
MCAST_PORT = 5000

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