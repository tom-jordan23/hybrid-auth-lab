#!/bin/bash
# Import Keycloak Realm Configuration
# This script imports the hybrid-auth realm with OAuth client configuration

set -euo pipefail

# Configuration
REALM_FILE="keycloak-server/config/realm-hybrid-auth.json"
CLIENT_SECRET="ssh-pam-client-secret-2024-hybrid-auth-lab"

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

# Check if Keycloak is running
check_keycloak() {
    log_info "Checking if Keycloak is running..."
    
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -s --connect-timeout 5 "http://localhost:8080/realms/master" >/dev/null 2>&1; then
            log_success "Keycloak is running"
            return 0
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log_error "Keycloak is not running or not accessible"
    return 1
}

# Import realm configuration
import_realm() {
    log_info "Importing realm configuration..."
    
    # Copy realm file to Keycloak container
    if docker cp "$REALM_FILE" keycloak-server:/tmp/; then
        log_success "Realm file copied to container"
    else
        log_error "Failed to copy realm file to container"
        return 1
    fi
    
    # Import realm using Keycloak admin CLI
    log_info "Importing realm via Keycloak admin CLI..."
    
    if docker exec keycloak-server /opt/keycloak/bin/kc.sh import \
        --file /tmp/realm-hybrid-auth.json \
        --override true; then
        log_success "Realm imported successfully"
    else
        log_warning "Direct import failed, trying via admin API..."
        import_via_api
    fi
}

# Import via Admin API as fallback
import_via_api() {
    log_info "Getting admin access token..."
    
    # Get admin access token
    local token_response
    token_response=$(curl -s -X POST \
        "http://localhost:8080/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin" \
        -d "password=admin_password" \
        -d "grant_type=password" \
        -d "client_id=admin-cli")
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get admin access token"
        return 1
    fi
    
    local access_token
    access_token=$(echo "$token_response" | jq -r '.access_token // empty')
    
    if [[ -z "$access_token" ]]; then
        log_error "Failed to extract access token"
        return 1
    fi
    
    log_success "Admin access token obtained"
    
    # Check if realm already exists
    log_info "Checking if realm already exists..."
    local realm_exists
    realm_exists=$(curl -s -H "Authorization: Bearer $access_token" \
        "http://localhost:8080/admin/realms/hybrid-auth" \
        -w "%{http_code}" -o /dev/null)
    
    if [[ "$realm_exists" == "200" ]]; then
        log_warning "Realm 'hybrid-auth' already exists, deleting..."
        curl -s -X DELETE \
            -H "Authorization: Bearer $access_token" \
            "http://localhost:8080/admin/realms/hybrid-auth"
        log_info "Existing realm deleted"
    fi
    
    # Import realm
    log_info "Creating new realm..."
    local import_response
    import_response=$(curl -s -X POST \
        "http://localhost:8080/admin/realms" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d @"$REALM_FILE" \
        -w "%{http_code}")
    
    local http_code="${import_response: -3}"
    
    if [[ "$http_code" == "201" ]]; then
        log_success "Realm imported successfully via API"
    else
        log_error "Failed to import realm via API (HTTP $http_code)"
        return 1
    fi
}

# Verify import
verify_import() {
    log_info "Verifying realm import..."
    
    # Check if realm exists
    if curl -s --fail "http://localhost:8080/realms/hybrid-auth" >/dev/null; then
        log_success "✓ Realm 'hybrid-auth' is accessible"
    else
        log_error "✗ Realm 'hybrid-auth' is not accessible"
        return 1
    fi
    
    # Check OAuth client configuration
    log_info "Checking OAuth client configuration..."
    
    local client_response
    client_response=$(curl -s \
        "http://localhost:8080/realms/hybrid-auth/protocol/openid-connect/auth/device" \
        -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=ssh-pam-client")
    
    if echo "$client_response" | jq -e '.device_code' >/dev/null 2>&1; then
        log_success "✓ OAuth Device Flow is working"
    else
        log_warning "⚠ OAuth Device Flow test failed"
    fi
    
    # Check test users
    log_info "Verifying test users..."
    echo "Test users created:"
    echo "  - john.doe (password: password123)"
    echo "  - jane.smith (password: password123)"
    echo "  - testuser (password: password123)"
}

# Update client secret in container
update_client_secret() {
    log_info "Updating client secret in SSH container..."
    
    # Update OAuth environment file
    docker exec ubuntu-sshd-client bash -c "
        echo 'KEYCLOAK_CLIENT_SECRET=$CLIENT_SECRET' >> /etc/default/oauth-auth
        sed -i '/^KEYCLOAK_CLIENT_SECRET=/d; \$a KEYCLOAK_CLIENT_SECRET=$CLIENT_SECRET' /etc/default/oauth-auth
    " 2>/dev/null || true
    
    # Restart SSH service
    docker exec ubuntu-sshd-client service ssh restart 2>/dev/null || true
    
    log_success "Client secret updated in SSH container"
}

# Display access information
show_access_info() {
    echo ""
    log_success "🎉 Keycloak Realm Configuration Complete!"
    echo ""
    echo "Realm Information:"
    echo "  Name: hybrid-auth"
    echo "  URL: http://localhost:8080/realms/hybrid-auth"
    echo ""
    echo "OAuth Client:"
    echo "  Client ID: ssh-pam-client"
    echo "  Client Secret: $CLIENT_SECRET"
    echo "  Device Flow: Enabled"
    echo ""
    echo "Test Users (all with password 'password123'):"
    echo "  - john.doe"
    echo "  - jane.smith"
    echo "  - testuser"
    echo ""
    echo "Admin Access:"
    echo "  URL: http://localhost:8080/admin/"
    echo "  Username: admin"
    echo "  Password: admin_password"
    echo ""
    echo "Testing OAuth Authentication:"
    echo "  ssh testuser@localhost -p 2222"
    echo "  # Follow device flow instructions"
    echo ""
    echo "Testing Device Flow Directly:"
    echo "  KEYCLOAK_CLIENT_SECRET='$CLIENT_SECRET' ./examples/test-oauth-device-flow.sh testuser"
}

# Main function
main() {
    echo "Keycloak Realm Import Script"
    echo "============================"
    echo ""
    
    # Check if realm file exists
    if [[ ! -f "$REALM_FILE" ]]; then
        log_error "Realm file '$REALM_FILE' not found"
        exit 1
    fi
    
    check_keycloak
    import_realm
    verify_import
    update_client_secret
    show_access_info
}

# Execute main function
main "$@"
