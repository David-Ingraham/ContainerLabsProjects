#!/bin/sh
# Prepare FRR container for Ansible network_cli access
# Creates dedicated user with vtysh as default shell

set -e

FRR_HOST="${1:-10.1.1.11}"
FRR_USER="frruser"
FRR_PASS="admin123"
FRR_ROOT_PASS="admin123"


echo "Target: $FRR_HOST"
echo "User: $FRR_USER"
USER_EXISTS=$(sshpass -p ${FRR_ROOT_PASS} ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@${FRR_HOST} "grep -c '^${FRR_USER}:' /etc/passwd || true")

if [ "$USER_EXISTS" -gt 0 ]; then
    echo "[INFO] User $FRR_USER already exists, updating configuration..."
else
    echo "[INFO] Creating user $FRR_USER..."
    sshpass -p ${FRR_ROOT_PASS} ssh -o StrictHostKeyChecking=no root@${FRR_HOST} "adduser -D ${FRR_USER}"
    echo "[OK] User created"
fi

# Set password
sshpass -p ${FRR_ROOT_PASS} ssh -o StrictHostKeyChecking=no root@${FRR_HOST} "echo '${FRR_USER}:${FRR_PASS}' | chpasswd"

# Add to frrvty group
sshpass -p ${FRR_ROOT_PASS} ssh -o StrictHostKeyChecking=no root@${FRR_HOST} "addgroup ${FRR_USER} frrvty 2>/dev/null || true"
# Set vtysh as default shell
sshpass -p ${FRR_ROOT_PASS} ssh -o StrictHostKeyChecking=no root@${FRR_HOST} "sed -i '/^${FRR_USER}:/s|:[^:]*$|:/usr/bin/vtysh|' /etc/passwd"

# Verify configuration

SHELL_CHECK=$(sshpass -p ${FRR_ROOT_PASS} ssh -o StrictHostKeyChecking=no root@${FRR_HOST} "grep '^${FRR_USER}:' /etc/passwd | cut -d: -f7")


sshpass -p ${FRR_ROOT_PASS} ssh -o StrictHostKeyChecking=no root@${FRR_HOST} "touch /etc/frr/bgpd.conf"
sshpass -p ${FRR_ROOT_PASS} ssh -o StrictHostKeyChecking=no root@${FRR_HOST} "chown frr:frr /etc/frr/bgpd.conf"
sshpass -p ${FRR_ROOT_PASS} ssh -o StrictHostKeyChecking=no root@${FRR_HOST} "chmod 640 /etc/frr/bgpd.conf"
sshpass -p ${FRR_ROOT_PASS} ssh -o StrictHostKeyChecking=no root@${FRR_HOST} "/usr/lib/frr/bgpd -d -F traditional -A 127.0.0.1"


if [ "$SHELL_CHECK" = "/usr/bin/vtysh" ]; then
    echo ""
    echo "=========================================="
    echo "[SUCCESS] FRR user prepared successfully"
    echo "=========================================="
    exit 0
else
    echo ""
    echo "=========================================="
    echo "[ERROR] Shell configuration failed"
    echo "=========================================="
    exit 1
fi

