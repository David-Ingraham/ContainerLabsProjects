import socket
import struct
import time

MCAST_GRP = '239.1.1.1'
MCAST_PORT = 5000
MESSAGE = b'Multicast test from host1'

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