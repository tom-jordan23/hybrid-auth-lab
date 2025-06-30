#!/bin/bash
set -e

echo "=== Installing Java ==="

# Install OpenJDK 11 (recommended for Keycloak)
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk

# Set JAVA_HOME
echo 'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64' | sudo tee -a /etc/environment
echo 'export PATH=$PATH:$JAVA_HOME/bin' | sudo tee -a /etc/environment

# Source the environment
source /etc/environment

# Verify Java installation
java -version
javac -version

echo "Java installation completed successfully"
