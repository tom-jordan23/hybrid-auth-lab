#!/bin/bash
# Quick Start Script for OAuth/PAM Authentication
# This script automates the setup of OAuth authentication for the hybrid auth lab

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_SECRET="${KEYCLOAK_CLIENT_SECRET:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running or not accessible"
        exit 1
    fi
}

# Check if containers are running
check_containers() {
    log_info "Checking if containers are running..."
    
    if ! docker ps | grep -q keycloak; then
        log_error "Keycloak container is not running. Please run './build.sh' first."
        exit 1
    fi
    
    if ! docker ps | grep -q ubuntu-sshd-client; then
        log_error "Ubuntu client container is not running. Please run './build.sh' first."
        exit 1
    fi
    
    log_success "Required containers are running"
}

# Wait for services to be ready
wait_for_services() {
    log_info "Waiting for services to be ready..."
    
    # Wait for Keycloak
    local keycloak_url="http://localhost:8080"
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -s --connect-timeout 5 "${keycloak_url}/realms/master" >/dev/null 2>&1; then
            log_success "Keycloak is ready"
            break
        fi
        
        echo -n "."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log_error "Keycloak failed to start within expected time"
        exit 1
    fi
    
    # Wait a bit more for full initialization
    sleep 10
}

# Setup OAuth/PAM in the container
setup_oauth_pam() {
    log_info "Setting up OAuth/PAM authentication in Ubuntu client..."
    
    if [[ -z "$CLIENT_SECRET" ]]; then
        log_warning "KEYCLOAK_CLIENT_SECRET not provided. You'll need to configure it manually later."
        CLIENT_SECRET="CHANGE_ME"
    fi
    
    # Execute setup script in container
    docker exec ubuntu-sshd-client bash -c "
        export KEYCLOAK_CLIENT_SECRET='$CLIENT_SECRET'
        /opt/scripts/setup-oauth-pam.sh setup
    "
    
    log_success "OAuth/PAM setup completed in container"
}

# Create test users
create_test_users() {
    log_info "Creating test OAuth users..."
    
    docker exec ubuntu-sshd-client bash -c "
        /opt/auth/manage_oauth_users.sh create john.doe 'John Doe' 'john.doe@example.com'
        /opt/auth/manage_oauth_users.sh create jane.smith 'Jane Smith' 'jane.smith@example.com'
        /opt/auth/manage_oauth_users.sh create testuser 'Test User' 'testuser@example.com'
    "
    
    log_success "Test users created"
}

# Test OAuth device flow
test_oauth_flow() {
    log_info "Testing OAuth Device Flow..."
    
    if [[ -z "$CLIENT_SECRET" || "$CLIENT_SECRET" == "CHANGE_ME" ]]; then
        log_warning "Client secret not set, skipping OAuth flow test"
        return 0
    fi
    
    # Set environment and run test
    export KEYCLOAK_URL="http://localhost:8080"
    export KEYCLOAK_REALM="hybrid-auth"
    export KEYCLOAK_CLIENT_ID="ssh-pam-client"
    export KEYCLOAK_CLIENT_SECRET="$CLIENT_SECRET"
    
    log_info "Running OAuth test (will timeout in 30 seconds if not completed)..."
    
    # Run test with timeout
    timeout 30s "${SCRIPT_DIR}/examples/test-oauth-device-flow.sh" testuser || {
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_warning "OAuth test timed out (this is expected in automated setup)"
        else
            log_warning "OAuth test failed or was interrupted"
        fi
    }
}

# Display setup information
show_setup_info() {
    echo ""
    log_success "🎉 OAuth/PAM Authentication Setup Complete!"
    echo ""
    echo "Your hybrid authentication lab is now ready with:"
    echo "  ✓ Keycloak running on http://localhost:8080"
    echo "  ✓ Ubuntu client with OAuth/PAM authentication"
    echo "  ✓ Test users created (john.doe, jane.smith, testuser)"
    echo ""
    echo "Next Steps:"
    echo ""
    echo "1. Configure Keycloak (if not done already):"
    echo "   - Open http://localhost:8080"
    echo "   - Follow docs/keycloak-setup-guide.md"
    echo "   - Create realm 'hybrid-auth'"
    echo "   - Set up LDAP/AD integration"
    echo "   - Create client 'ssh-pam-client'"
    echo "   - Enable OAuth Device Flow"
    echo ""
    echo "2. Update client secret (if not provided):"
    echo "   docker exec ubuntu-sshd-client bash -c \\"
    echo "     \"echo 'KEYCLOAK_CLIENT_SECRET=your_actual_secret' >> /etc/default/oauth-auth\""
    echo "   docker exec ubuntu-sshd-client systemctl restart ssh"
    echo ""
    echo "3. Test SSH login with OAuth:"
    echo "   ssh john.doe@localhost -p 2222"
    echo "   # Follow device flow instructions in browser"
    echo ""
    echo "4. Test OAuth Device Flow directly:"
    echo "   KEYCLOAK_CLIENT_SECRET=your_secret ./examples/test-oauth-device-flow.sh testuser"
    echo ""
    echo "Useful commands:"
    echo "  - docker exec ubuntu-sshd-client oauth-users    # List OAuth users"
    echo "  - docker exec ubuntu-sshd-client oauth-create   # Create OAuth user"
    echo "  - ./network-info.sh                        # Show network information"
    echo "  - ./export-config.sh                       # Export configurations"
    echo ""
    
    if [[ -z "$CLIENT_SECRET" || "$CLIENT_SECRET" == "CHANGE_ME" ]]; then
        echo ""
        log_warning "IMPORTANT: Remember to set the Keycloak client secret!"
        echo "1. Get the secret from Keycloak admin console"
        echo "2. Update it in the container:"
        echo "   docker exec ubuntu-sshd-client bash -c \\"
        echo "     \"sed -i 's/KEYCLOAK_CLIENT_SECRET=.*/KEYCLOAK_CLIENT_SECRET=your_actual_secret/' /etc/default/oauth-auth\""
        echo "3. Restart SSH service:"
        echo "   docker exec ubuntu-sshd-client systemctl restart ssh"
    fi
}

# Restore function
restore_setup() {
    log_info "Restoring original configuration..."
    
    docker exec ubuntu-sshd-client bash -c "
        /opt/scripts/setup-oauth-pam.sh restore
    " || log_warning "Restore command failed (container might not be running)"
    
    log_success "Configuration restored"
}

# Main function
main() {
    case "${1:-setup}" in
        setup)
            echo "OAuth/PAM Quick Start Setup"
            echo "=========================="
            echo ""
            
            check_docker
            check_containers
            wait_for_services
            setup_oauth_pam
            create_test_users
            test_oauth_flow
            show_setup_info
            ;;
        
        restore)
            restore_setup
            ;;
        
        test)
            check_docker
            check_containers
            test_oauth_flow
            ;;
        
        help|--help|-h)
            echo "OAuth/PAM Quick Start Script"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  setup    - Setup OAuth/PAM authentication (default)"
            echo "  restore  - Restore original configuration"
            echo "  test     - Test OAuth Device Flow"
            echo "  help     - Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  KEYCLOAK_CLIENT_SECRET - Keycloak client secret"
            echo ""
            echo "Prerequisites:"
            echo "  - Docker and Docker Compose installed"
            echo "  - Containers running (./build.sh)"
            echo "  - Keycloak configured with realm and client"
            ;;
        
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
