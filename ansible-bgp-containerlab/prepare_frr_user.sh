#!/bin/sh
# Prepare FRR container for Ansible network_cli access
# Creates dedicated user with vtysh as default shell

set -e

FRR_HOST="${1:-10.1.1.11}"
FRR_USER="frruser"
FRR_PASS="admin123"
FRR_ROOT_PASS="admin123"

# Helper function for single commands (when we need output)
ssh_exec() {
    sshpass -p "${FRR_ROOT_PASS}" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@${FRR_HOST} "$@"
}

echo "Target: $FRR_HOST"
echo "User: $FRR_USER"

# Check if user exists (needs output, so separate SSH call)
USER_EXISTS=$(ssh_exec "grep -c '^${FRR_USER}:' /etc/passwd || true")

if [ "$USER_EXISTS" -gt 0 ]; then
    echo "[INFO] User $FRR_USER already exists, updating configuration..."
else
    echo "[INFO] Creating user $FRR_USER..."
fi

# Execute all configuration commands in a single SSH session
sshpass -p "${FRR_ROOT_PASS}" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@${FRR_HOST} << EOF
# Create user if needed (adduser is idempotent with -D flag handling)
if ! id "${FRR_USER}" >/dev/null 2>&1; then
    adduser -D ${FRR_USER}
fi

# Set password
echo '${FRR_USER}:${FRR_PASS}' | chpasswd

# Add to frrvty group
addgroup ${FRR_USER} frrvty 2>/dev/null || true

# Set vtysh as default shell for frr user
sed -i '/^${FRR_USER}:/s|:[^:]*\$|:/usr/bin/vtysh|' /etc/passwd

# create conf BGP daemon files, chown and chmod to frr user
touch /etc/frr/bgpd.conf
chown frr:frr /etc/frr/bgpd.conf
chmod 640 /etc/frr/bgpd.conf

# Start BGP daemon
/usr/lib/frr/bgpd -d -F traditional -A 127.0.0.1

# Create conf vtysh files, chown and chmod to frr user
touch /etc/frr/vtysh.conf
chown frr:frr /etc/frr/vtysh.conf
chmod 640 /etc/frr/vtysh.conf
EOF

echo "[OK] Configuration applied"

# Verify configuration (needs output, so separate SSH call)
SHELL_CHECK=$(ssh_exec "grep '^${FRR_USER}:' /etc/passwd | cut -d: -f7")

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
    echo "Expected: /usr/bin/vtysh"
    echo "Got: $SHELL_CHECK"
    echo "=========================================="
    exit 1
fi