#!/bin/bash
set -e

echo "=== Updating System ==="

# Update package lists
sudo apt-get update

# Upgrade system packages
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install essential packages
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    curl \
    wget \
    vim \
    htop \
    net-tools \
    unzip \
    systemd \
    dbus

# Set timezone
sudo timedatectl set-timezone UTC

echo "System update completed successfully"
