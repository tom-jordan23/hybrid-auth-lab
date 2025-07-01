#!/bin/bash
set -e

echo "=== Hybrid Authentication Lab Build Script ==="
echo "Building OAuth + Active Directory integration"
echo ""

# Check if Windows AD is running (required for full setup)
check_windows_ad() {
    echo "Checking Windows Active Directory status..."
    
    if [ ! -d "windows-ad-server" ]; then
        echo "❌ Error: Windows AD server directory not found"
        echo "This project requires Windows Active Directory integration."
        echo ""
        echo "Please run:"
        echo "  git submodule update --init --recursive"
        echo "  cd windows-ad-server && ./build-vm.sh && ./start-vm.sh"
        exit 1
    fi
    
    # Check if Windows VM is built
    if [ ! -f "windows-ad-server/windows_2022_like_2019-qemu/WindowsServer2022-Like2019" ]; then
        echo "❌ Windows AD server not built yet"
        echo ""
        echo "Building Windows AD is required for this hybrid authentication lab."
        echo "Please run:"
        echo "  cd windows-ad-server"
        echo "  ./build-vm.sh    # Takes 15-20 minutes"
        echo "  ./start-vm.sh    # Start the domain controller"
        echo "  ./status.sh      # Verify it's running"
        echo "  cd .. && ./build.sh"
        exit 1
    fi
    
    # Check if Windows VM is running
    if ! pgrep -f "WindowsServer2022-Like2019" >/dev/null; then
        echo "❌ Windows AD server is not running"
        echo ""
        echo "Please start Windows AD first:"
        echo "  cd windows-ad-server && ./start-vm.sh && cd .."
        echo "Then run this script again."
        exit 1
    fi
    
    # Check if LDAP port is accessible
    if ! nc -z localhost 389 2>/dev/null; then
        echo "⚠️  Windows AD is starting but LDAP (port 389) not yet accessible"
        echo "Waiting for Active Directory services to start..."
        
        local max_wait=60
        local wait_time=0
        while [ $wait_time -lt $max_wait ]; do
            if nc -z localhost 389 2>/dev/null; then
                echo "✅ LDAP port 389 is now accessible"
                break
            fi
            echo -n "."
            sleep 5
            wait_time=$((wait_time + 5))
        done
        
        if [ $wait_time -ge $max_wait ]; then
            echo ""
            echo "❌ Timeout waiting for LDAP. Check Windows AD status:"
            echo "  cd windows-ad-server && ./status.sh"
            exit 1
        fi
    else
        echo "✅ Windows Active Directory is running with LDAP accessible"
    fi
}

# Check Windows AD first
check_windows_ad
echo "Building complete OAuth + Active Directory integration"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        echo "Install: https://docs.docker.com/get-docker/"
        exit 1
    fi
    log_success "Docker is installed"
    
    # Check Docker Compose
    DOCKER_COMPOSE_CMD=""
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
        log_success "Docker Compose is available"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
        log_success "Docker Compose (legacy) is available"
    else
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check Packer (required for Windows AD)
    if ! command -v packer &> /dev/null; then
        log_error "Packer is not installed. This is REQUIRED for Windows AD server."
        echo "Install: https://www.packer.io/downloads"
        echo "Ubuntu/Debian: sudo apt install packer"
        echo "Fedora/RHEL: sudo dnf install packer"
        exit 1
    fi
    log_success "Packer is installed"
    
    # Check QEMU (required for Windows AD)
    if ! command -v qemu-system-x86_64 &> /dev/null; then
        log_error "QEMU is not installed. This is REQUIRED for Windows AD server."
        echo "Ubuntu/Debian: sudo apt-get install qemu-kvm qemu-system-x86"
        echo "Fedora/RHEL: sudo dnf install qemu-kvm qemu-system-x86"
        exit 1
    fi
    log_success "QEMU is installed"
    
    # Check KVM group membership
    if ! groups | grep -q kvm; then
        log_warning "User not in 'kvm' group. This may cause VM issues."
        echo "Fix: sudo usermod -a -G kvm \$USER && logout/login"
        echo "Continuing anyway..."
    else
        log_success "User is in 'kvm' group"
    fi
    
    # Check jq (required for OAuth scripts)
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. This is REQUIRED for OAuth scripts."
        echo "Ubuntu/Debian: sudo apt install jq"
        echo "Fedora/RHEL: sudo dnf install jq"
        exit 1
    fi
    log_success "jq is installed"
    
    echo ""
}

# Build Docker services
build_docker_services() {
    log_info "Building Docker services (OAuth + SSH)..."
    
    echo "Building Docker images..."
    $DOCKER_COMPOSE_CMD build
    
    echo "Starting services..."
    $DOCKER_COMPOSE_CMD up -d
    
    echo "Waiting for services to be ready..."
    sleep 15
    
    # Check service status
    echo ""
    log_info "Checking Docker service status..."
    $DOCKER_COMPOSE_CMD ps
    
    # Health checks
    echo ""
    log_info "Running health checks..."
    
    # Check Keycloak
    echo -n "Checking Keycloak... "
    local max_attempts=30
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -s -f http://localhost:8080/health/ready > /dev/null 2>&1; then
            log_success "Keycloak is ready"
            break
        fi
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log_warning "Keycloak taking longer than expected to start"
    fi
    
    # Check Ubuntu SSHD
    echo -n "Checking Ubuntu SSHD... "
    if nc -z localhost 2222; then
        log_success "SSH server is ready"
    else
        log_warning "SSH server not ready"
    fi
    
    echo ""
}

# Build Windows AD server
build_windows_ad() {
    log_info "Building Windows Active Directory server..."
    
    cd windows-ad-server
    
    # Check if already built
    if [ -f "windows_2022_like_2019-qemu/WindowsServer2022-Like2019" ]; then
        log_info "Windows AD VM already exists. Skipping build."
        log_info "To rebuild, delete windows_2022_like_2019-qemu/ directory"
    else
        log_info "Building Windows Server 2022 with Active Directory..."
        log_warning "This will take 15-20 minutes and download ~5GB"
        echo ""
        ./build-vm.sh
        log_success "Windows AD VM built successfully"
    fi
    
    echo ""
    log_info "Starting Windows AD server..."
    ./start-vm.sh
    
    echo ""
    log_info "Waiting for Windows AD to start (this takes a few minutes)..."
    sleep 30
    
    # Check VM status
    if ./status.sh | grep -q "VM is running"; then
        log_success "Windows AD VM is running"
    else
        log_error "Windows AD VM failed to start"
        cd ..
        exit 1
    fi
    
    cd ..
    echo ""
}

# Configure integration
configure_integration() {
    log_info "Configuring Keycloak <-> Active Directory integration..."
    
    # Wait for AD to be fully ready
    log_info "Waiting for Active Directory to be fully initialized..."
    echo "This can take 5-10 minutes for domain services to start..."
    
    local max_attempts=60
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if nc -z localhost 389 2>/dev/null; then
            log_success "Active Directory LDAP is accessible"
            break
        fi
        echo -n "."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log_warning "LDAP not accessible yet. You may need to configure manually."
        log_info "The realm configuration includes LDAP settings for when AD is ready"
        return 0
    fi
    
    # Import updated realm with LDAP configuration
    log_info "Importing Keycloak realm with Active Directory integration..."
    ./import-keycloak-realm.sh
    
    log_success "Integration configured"
    echo ""
}

# Main execution
main() {
    check_prerequisites
    
    echo "=== Building Complete Hybrid Authentication Lab ==="
    echo "This includes:"
    echo "  ✓ Keycloak OAuth Server"
    echo "  ✓ Ubuntu SSH Server with OAuth PAM"
    echo "  ✓ Windows Server 2022 Active Directory"
    echo "  ✓ LDAP Federation (Keycloak <-> AD)"
    echo ""
    
    read -p "Continue with full build? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Build cancelled. For Docker-only build, use: docker compose up -d"
        exit 0
    fi
    
    build_docker_services
    build_windows_ad
    configure_integration
    
    echo ""
    echo "=== 🎉 Hybrid Authentication Lab Ready! ==="
    echo ""
    log_success "All services are running:"
    echo "  • Keycloak OAuth Server: http://localhost:8080"
    echo "    - Admin: admin/admin_password"
    echo "    - Realm: hybrid-auth"
    echo "    - LDAP: Configured for Windows AD"
    echo ""
    echo "  • Ubuntu SSH Server: ssh testuser@localhost -p 2222"
    echo "    - Authentication: OAuth Device Flow"
    echo "    - User Source: Active Directory via Keycloak"
    echo ""
    echo "  • Windows AD Server: RDP to localhost:3389"
    echo "    - Domain: hybrid.local"
    echo "    - LDAP: localhost:389"
    echo "    - Admin: Administrator/[see VM scripts]"
    echo ""
    log_info "Test the integration:"
    echo "  ./test-oauth-integration.sh       # Test OAuth setup"
    echo "  ./demo-oauth-device-flow.sh       # Try device flow"
    echo "  ssh aduser@localhost -p 2222      # SSH with AD user"
    echo ""
    log_info "Management commands:"
    echo "  ./check-status.sh                 # Check all services"
    echo "  ./config-manager.sh export        # Export configurations"
    echo "  docker compose logs -f            # View Docker logs"
    echo "  cd windows-ad-server && ./status.sh  # Check Windows VM"
    echo ""
    echo "For troubleshooting, see: GETTING-STARTED.md"
}

# Run main function
main "$@"
