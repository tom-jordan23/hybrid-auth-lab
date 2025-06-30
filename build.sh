#!/bin/bash
set -e

echo "=== Hybrid Auth Lab Build Script ==="

# Check if Docker and Docker Compose are installed
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed. Please install Docker first."
    exit 1
fi

# Check for docker compose (newer) or docker-compose (older)
DOCKER_COMPOSE_CMD=""
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo "Error: Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

echo "Using: $DOCKER_COMPOSE_CMD"

# Check if Packer is installed (for Windows VM)
if ! command -v packer &> /dev/null; then
    echo "Warning: Packer is not installed. You won't be able to build the Windows AD server."
    echo "Install Packer from: https://www.packer.io/downloads"
fi

# Check if QEMU is installed (for Windows VM)
if ! command -v qemu-system-x86_64 &> /dev/null; then
    echo "Warning: QEMU is not installed. You won't be able to run the Windows AD server."
    echo "Install QEMU: sudo apt-get install qemu-kvm qemu-system-x86-64"
fi

echo ""
echo "=== Building Docker Services ==="

# Build and start Docker services
echo "Building Docker images..."
$DOCKER_COMPOSE_CMD build

echo "Starting services..."
$DOCKER_COMPOSE_CMD up -d

echo "Waiting for services to be ready..."
sleep 10

# Check service status
echo ""
echo "=== Service Status ==="
$DOCKER_COMPOSE_CMD ps

echo ""
echo "=== Service Health Checks ==="

# Check Keycloak
echo -n "Checking Keycloak... "
if curl -s -f http://localhost:8080/health/ready > /dev/null 2>&1; then
    echo "✓ Ready"
else
    echo "✗ Not ready (may need more time)"
fi

# Check Ubuntu SSHD
echo -n "Checking Ubuntu SSHD... "
if nc -z localhost 2222; then
    echo "✓ Ready"
else
    echo "✗ Not ready"
fi

echo ""
echo "=== Access Information ==="
echo "Keycloak Admin Console: http://localhost:8080"
echo "  Username: admin"
echo "  Password: admin_password"
echo ""
echo "Ubuntu SSHD Client: ssh vagrant@localhost -p 2222"
echo "  Password: vagrant"
echo ""
echo "=== Network Access ==="
echo "Run './network-info.sh' to see local network access information"
echo ""
echo "=== Next Steps ==="
echo "1. Access Keycloak and configure your realm"
echo "2. Test SSH access to Ubuntu client"
echo "3. Build Windows AD server: cd windows-ad-server && packer build windows-2022-ad-ldif.json"
echo "4. Configure authentication integration between services"
echo "5. Run './network-info.sh' to see how to access from other devices"
echo ""
echo "View logs: $DOCKER_COMPOSE_CMD logs -f"
echo "Stop services: $DOCKER_COMPOSE_CMD down"
