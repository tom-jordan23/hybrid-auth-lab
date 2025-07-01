#!/bin/bash
# Complete Lab Environment Status Check
# This script verifies all components of the hybrid auth lab

set -euo pipefail

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

echo "=== Hybrid Authentication Lab Status Check ==="
echo ""

# Check Docker components
log_info "Checking Docker components..."

if command -v docker >/dev/null 2>&1; then
    log_success "Docker is installed"
else
    log_error "Docker is not installed"
    exit 1
fi

if command -v docker-compose >/dev/null 2>&1 || docker compose version >/dev/null 2>&1; then
    log_success "Docker Compose is available"
else
    log_error "Docker Compose is not installed"
    exit 1
fi

# Check if containers are running
if docker compose ps | grep -q "Up"; then
    log_success "Docker containers are running"
    
    # Check specific containers
    if docker compose ps | grep -q "keycloak-server.*Up"; then
        log_success "Keycloak server is running"
        
        # Test Keycloak accessibility
        if curl -s --connect-timeout 5 "http://localhost:8080/realms/hybrid-auth" >/dev/null 2>&1; then
            log_success "Keycloak is accessible on port 8080"
        else
            log_warning "Keycloak container running but not accessible yet (may still be starting)"
        fi
    else
        log_error "Keycloak server is not running"
    fi
    
    if docker compose ps | grep -q "ubuntu-sshd-client.*Up"; then
        log_success "Ubuntu SSH server is running"
        
        # Test SSH port
        if nc -z localhost 2222 2>/dev/null; then
            log_success "SSH server is accessible on port 2222"
        else
            log_warning "SSH container running but port 2222 not accessible yet"
        fi
    else
        log_error "Ubuntu SSH server is not running"
    fi
    
    if docker compose ps | grep -q "keycloak-db.*Up"; then
        log_success "Keycloak database is running"
    else
        log_warning "Keycloak database container not found"
    fi
    
else
    log_error "No Docker containers are running"
    echo "Run: ./build.sh"
fi

echo ""

# Check Windows AD server
log_info "Checking Windows AD server..."

if [ -d "windows-ad-server" ]; then
    cd windows-ad-server
    
    if [ -f "windows_2022_like_2019-qemu/WindowsServer2022-Like2019" ]; then
        log_success "Windows VM disk file exists"
        
        # Check if VM is running
        VM_PID=$(pgrep -f "WindowsServer2022-Like2019" || echo "")
        if [ -n "$VM_PID" ]; then
            log_success "Windows VM is running (PID: $VM_PID)"
            
            # Check AD ports
            if nc -z localhost 389 2>/dev/null; then
                log_success "Active Directory LDAP (389) is accessible"
            else
                log_warning "LDAP port 389 not accessible (AD may still be starting)"
            fi
            
            if nc -z localhost 3389 2>/dev/null; then
                log_success "RDP (3389) is accessible"
            else
                log_warning "RDP port 3389 not accessible"
            fi
            
        else
            log_warning "Windows VM is not running"
            echo "         To start: cd windows-ad-server && ./start-vm.sh"
        fi
    else
        log_warning "Windows VM not built yet"
        echo "         To build: cd windows-ad-server && ./build-vm.sh"
    fi
    
    cd ..
else
    log_error "Windows AD server directory not found"
fi

echo ""

# Check OAuth integration
log_info "Testing OAuth integration..."

if curl -s --connect-timeout 5 "http://localhost:8080/realms/hybrid-auth" >/dev/null 2>&1; then
    # Test OAuth device flow endpoint
    DEVICE_RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=ssh-pam-client&client_secret=ssh-pam-client-secret-2024-hybrid-auth-lab" \
        "http://localhost:8080/realms/hybrid-auth/protocol/openid-connect/auth/device" 2>/dev/null || echo "")
    
    if echo "$DEVICE_RESPONSE" | jq -e '.device_code' >/dev/null 2>&1; then
        log_success "OAuth Device Flow endpoint is working"
    else
        log_error "OAuth Device Flow endpoint failed"
        echo "Response: $DEVICE_RESPONSE"
    fi
else
    log_warning "Keycloak not accessible, skipping OAuth test"
fi

echo ""

# Check system prerequisites
log_info "Checking system prerequisites..."

if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    log_success "QEMU is installed"
else
    log_warning "QEMU is not installed (needed for Windows VM)"
    echo "         Install: sudo apt install qemu-kvm qemu-system-x86 (Ubuntu/Debian)"
fi

if command -v packer >/dev/null 2>&1; then
    log_success "Packer is installed"
else
    log_warning "Packer is not installed (needed to build Windows VM)"
    echo "         Download: https://www.packer.io/downloads"
fi

if groups | grep -q kvm; then
    log_success "User is in kvm group"
else
    log_warning "User not in kvm group (needed for QEMU/KVM)"
    echo "         Fix: sudo usermod -a -G kvm \$USER && logout/login"
fi

if command -v jq >/dev/null 2>&1; then
    log_success "jq is installed"
else
    log_error "jq is not installed (required for OAuth scripts)"
    echo "         Install: sudo apt install jq"
fi

echo ""

# Summary and next steps
echo "=== Summary ==="

DOCKER_OK=$(docker compose ps | grep -q "Up" && echo "true" || echo "false")
KEYCLOAK_OK=$(curl -s --connect-timeout 5 "http://localhost:8080/realms/hybrid-auth" >/dev/null 2>&1 && echo "true" || echo "false")
WINDOWS_BUILT=$([ -f "windows-ad-server/windows_2022_like_2019-qemu/WindowsServer2022-Like2019" ] && echo "true" || echo "false")
WINDOWS_RUNNING=$(pgrep -f "WindowsServer2022-Like2019" >/dev/null && echo "true" || echo "false")

if [ "$DOCKER_OK" = "true" ] && [ "$KEYCLOAK_OK" = "true" ]; then
    echo -e "${GREEN}✅ Docker OAuth Environment: Ready${NC}"
    echo "   Test with: ./test-oauth-integration.sh"
    echo "   Try SSH: ssh testuser@localhost -p 2222"
else
    echo -e "${RED}❌ Docker OAuth Environment: Not Ready${NC}"
    echo "   Run: ./build.sh"
fi

if [ "$WINDOWS_BUILT" = "true" ]; then
    if [ "$WINDOWS_RUNNING" = "true" ]; then
        echo -e "${GREEN}✅ Windows AD Environment: Running${NC}"
        echo "   Connect via RDP: rdesktop localhost:3389"
        echo "   LDAP available on: localhost:389"
    else
        echo -e "${YELLOW}⚠️  Windows AD Environment: Built but not running${NC}"
        echo "   Start: cd windows-ad-server && ./start-vm.sh"
    fi
else
    echo -e "${YELLOW}⚠️  Windows AD Environment: Not built${NC}"
    echo "   Build: cd windows-ad-server && ./build-vm.sh"
fi

echo ""
echo "=== Quick Start Commands ==="
echo "  Minimal setup (Docker only): ./build.sh"
echo "  Full setup: ./build.sh && cd windows-ad-server && ./build-vm.sh && ./start-vm.sh"
echo "  Test OAuth: ./demo-oauth-device-flow.sh"
echo "  Test SSH: ssh testuser@localhost -p 2222"
echo ""
echo "For detailed guides, see: docs/ directory or GETTING-STARTED.md"
