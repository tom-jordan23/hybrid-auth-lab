#!/bin/bash
set -e

echo "Starting Ubuntu SSHD container services..."

# Set root password if provided
if [ ! -z "$ROOT_PASSWORD" ]; then
    echo "root:$ROOT_PASSWORD" | chpasswd
fi

# Set vagrant user password if provided
if [ ! -z "$USER_PASSWORD" ]; then
    echo "vagrant:$USER_PASSWORD" | chpasswd
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
exec "$@" &
wait $!
