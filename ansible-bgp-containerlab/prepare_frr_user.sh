#!/bin/sh
# Prepare FRR container for Ansible network_cli access
# Creates dedicated user with vtysh as default shell

set -e

FRR_HOST="${1:-10.1.1.11}"
FRR_USER="frruser"
FRR_PASS="admin123"
FRR_ROOT_PASS="admin123"

echo "=========================================="
echo "Preparing FRR User for Ansible Access"
echo "=========================================="
echo "Target: $FRR_HOST"
echo "User: $FRR_USER"
echo ""

# Check if user already exists
USER_EXISTS=$(sshpass -p ${FRR_ROOT_PASS} ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@${FRR_HOST} "grep -c '^${FRR_USER}:' /etc/passwd || true")

if [ "$USER_EXISTS" -gt 0 ]; then
    echo "[INFO] User $FRR_USER already exists, updating configuration..."
else
    echo "[INFO] Creating user $FRR_USER..."
    sshpass -p ${FRR_ROOT_PASS} ssh -o StrictHostKeyChecking=no root@${FRR_HOST} "adduser -D ${FRR_USER}"
    echo "[OK] User created"
fi

# Set password
echo "[INFO] Setting password..."
sshpass -p ${FRR_ROOT_PASS} ssh -o StrictHostKeyChecking=no root@${FRR_HOST} "echo '${FRR_USER}:${FRR_PASS}' | chpasswd"
echo "[OK] Password set"

# Add to frrvty group
echo "[INFO] Adding to frrvty group..."
sshpass -p ${FRR_ROOT_PASS} ssh -o StrictHostKeyChecking=no root@${FRR_HOST} "addgroup ${FRR_USER} frrvty 2>/dev/null || true"
echo "[OK] Group membership configured"

# Set vtysh as default shell
echo "[INFO] Setting vtysh as default shell..."
sshpass -p ${FRR_ROOT_PASS} ssh -o StrictHostKeyChecking=no root@${FRR_HOST} "sed -i '/^${FRR_USER}:/s|:[^:]*$|:/usr/bin/vtysh|' /etc/passwd"
echo "[OK] Shell configured"

# Verify configuration
echo ""
echo "[INFO] Verifying configuration..."
SHELL_CHECK=$(sshpass -p ${FRR_ROOT_PASS} ssh -o StrictHostKeyChecking=no root@${FRR_HOST} "grep '^${FRR_USER}:' /etc/passwd | cut -d: -f7")
echo "User shell: $SHELL_CHECK"

if [ "$SHELL_CHECK" = "/usr/bin/vtysh" ]; then
    echo ""
    echo "=========================================="
    echo "[SUCCESS] FRR user prepared successfully!"
    echo "=========================================="
    exit 0
else
    echo ""
    echo "=========================================="
    echo "[ERROR] Shell configuration failed!"
    echo "=========================================="
    exit 1
fi

