#!/bin/bash
set -e

echo "Starting Ubuntu SSHD container services..."

# Set root password if provided
if [ ! -z "$ROOT_PASSWORD" ]; then
    echo "root:$ROOT_PASSWORD" | chpasswd 2>/dev/null || echo "root:$ROOT_PASSWORD" | chpasswd
fi

# Set vagrant user password if provided
if [ ! -z "$USER_PASSWORD" ]; then
    echo "vagrant:$USER_PASSWORD" | chpasswd 2>/dev/null || echo "vagrant:$USER_PASSWORD" | chpasswd
fi

# Start systemd services
echo "Starting SSH service..."
service ssh start

# Start SSSD if configuration exists
if [ -f /etc/sssd/sssd.conf ]; then
    echo "Starting SSSD service..."
    service sssd start
fi

echo "Services started successfully"
echo "SSH server is ready on port 22"
echo "Available users: root, vagrant"

# Keep container running
if [ $# -eq 0 ]; then
    # No command provided, just keep container alive
    tail -f /dev/null
else
    # Execute provided command
    exec "$@"
fi
