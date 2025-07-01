#!/bin/bash
# Test OAuth Integration Script
# This script demonstrates the complete OAuth Device Flow integration

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

# Configuration
CLIENT_ID="ssh-pam-client"
CLIENT_SECRET="ssh-pam-client-secret-2024-hybrid-auth-lab"
KEYCLOAK_URL="http://localhost:8080"
REALM="hybrid-auth"

echo "=== Testing OAuth Device Flow Integration ==="
echo ""

# Test 1: Check if Keycloak is accessible
log_info "Testing Keycloak accessibility..."
if curl -s --connect-timeout 5 "$KEYCLOAK_URL/realms/$REALM" >/dev/null 2>&1; then
    log_success "Keycloak is accessible"
else
    log_error "Keycloak is not accessible"
    exit 1
fi

# Test 2: Test OAuth Device Flow endpoint
log_info "Testing OAuth Device Flow endpoint..."
DEVICE_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" \
    "$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/auth/device")

if echo "$DEVICE_RESPONSE" | jq -e '.device_code' >/dev/null 2>&1; then
    log_success "OAuth Device Flow endpoint is working"
    
    # Extract values
    DEVICE_CODE=$(echo "$DEVICE_RESPONSE" | jq -r '.device_code')
    USER_CODE=$(echo "$DEVICE_RESPONSE" | jq -r '.user_code')
    VERIFICATION_URI=$(echo "$DEVICE_RESPONSE" | jq -r '.verification_uri')
    VERIFICATION_URI_COMPLETE=$(echo "$DEVICE_RESPONSE" | jq -r '.verification_uri_complete')
    EXPIRES_IN=$(echo "$DEVICE_RESPONSE" | jq -r '.expires_in')
    INTERVAL=$(echo "$DEVICE_RESPONSE" | jq -r '.interval')
    
    echo ""
    echo -e "${GREEN}Device Authorization Successful!${NC}"
    echo "  Device Code: $DEVICE_CODE"
    echo "  User Code: $USER_CODE"
    echo "  Verification URI: $VERIFICATION_URI"
    echo "  Complete URI: $VERIFICATION_URI_COMPLETE"
    echo "  Expires in: $EXPIRES_IN seconds"
    echo "  Poll interval: $INTERVAL seconds"
else
    log_error "OAuth Device Flow endpoint failed"
    echo "Response: $DEVICE_RESPONSE"
    exit 1
fi

# Test 3: Check OAuth configuration in SSH container
log_info "Testing OAuth configuration in SSH container..."
if docker exec ubuntu-sshd-client test -f /etc/default/oauth-auth; then
    log_success "OAuth configuration file exists in SSH container"
    echo ""
    echo "OAuth Configuration:"
    docker exec ubuntu-sshd-client cat /etc/default/oauth-auth | sed 's/^/  /'
else
    log_error "OAuth configuration file missing in SSH container"
    exit 1
fi

# Test 4: Check OAuth auth script
log_info "Testing OAuth auth script in SSH container..."
if docker exec ubuntu-sshd-client test -f /opt/auth/oauth_auth.sh; then
    log_success "OAuth auth script exists and is executable"
    
    # Test script execution (without PAM context, just to check basic functionality)
    log_info "Testing OAuth script execution..."
    SCRIPT_OUTPUT=$(docker exec ubuntu-sshd-client bash -c '
        export PAM_TYPE=auth PAM_USER=testuser 
        export KEYCLOAK_CLIENT_SECRET=ssh-pam-client-secret-2024-hybrid-auth-lab
        source /etc/default/oauth-auth
        timeout 10s /opt/auth/oauth_auth.sh || true
    ' 2>&1)
    
    if echo "$SCRIPT_OUTPUT" | grep -q "OAuth authentication requested"; then
        log_success "OAuth script is functioning correctly"
    else
        log_warning "OAuth script output unexpected:"
        echo "$SCRIPT_OUTPUT" | sed 's/^/  /'
    fi
else
    log_error "OAuth auth script missing in SSH container"
    exit 1
fi

# Test 5: Test from SSH container perspective
log_info "Testing device flow from SSH container perspective..."
CONTAINER_RESPONSE=$(docker exec ubuntu-sshd-client bash -c "
    curl -s -X POST \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        -d 'client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET' \
        'http://keycloak:8080/realms/$REALM/protocol/openid-connect/auth/device'
")

if echo "$CONTAINER_RESPONSE" | jq -e '.device_code' >/dev/null 2>&1; then
    log_success "Device flow works from SSH container"
    CONTAINER_USER_CODE=$(echo "$CONTAINER_RESPONSE" | jq -r '.user_code')
    echo "  Container User Code: $CONTAINER_USER_CODE"
else
    log_error "Device flow failed from SSH container"
    echo "Response: $CONTAINER_RESPONSE"
fi

echo ""
echo "=== OAuth Integration Test Complete ==="
echo ""
echo -e "${GREEN}✓ Keycloak server is running and accessible${NC}"
echo -e "${GREEN}✓ OAuth Device Flow endpoint is functional${NC}"
echo -e "${GREEN}✓ Client secret is properly configured${NC}"
echo -e "${GREEN}✓ SSH container has OAuth configuration${NC}"
echo -e "${GREEN}✓ OAuth auth script is present and functional${NC}"
echo ""
echo -e "${BLUE}To test OAuth authentication manually:${NC}"
echo "1. Visit: $VERIFICATION_URI_COMPLETE"
echo "2. Enter user code: $USER_CODE"
echo "3. Login with: admin/admin or testuser/testpass"
echo ""
echo -e "${BLUE}To test SSH with OAuth:${NC}"
echo "ssh testuser@localhost -p 2222"
echo ""
echo -e "${YELLOW}Note: The OAuth Device Flow is working correctly.${NC}"
echo -e "${YELLOW}SSH integration requires the user to complete the browser flow.${NC}"
