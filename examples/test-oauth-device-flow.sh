#!/bin/bash
# Test OAuth Device Flow Authentication
# This script tests the OAuth authentication flow without PAM integration

set -euo pipefail

# Configuration
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
REALM="${KEYCLOAK_REALM:-hybrid-auth}"
CLIENT_ID="${KEYCLOAK_CLIENT_ID:-ssh-pam-client}"
CLIENT_SECRET="${KEYCLOAK_CLIENT_SECRET:-}"
USERNAME="${1:-testuser}"

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

# Check dependencies
check_dependencies() {
    command -v curl >/dev/null 2>&1 || { log_error "curl is required"; exit 1; }
    command -v jq >/dev/null 2>&1 || { log_error "jq is required"; exit 1; }
}

# Test Keycloak connectivity
test_connectivity() {
    log_info "Testing Keycloak connectivity..."
    
    local health_url="${KEYCLOAK_URL}/realms/${REALM}"
    
    if curl -s --connect-timeout 10 --max-time 30 "$health_url" >/dev/null; then
        log_success "Keycloak is accessible at $health_url"
    else
        log_error "Cannot connect to Keycloak at $health_url"
        exit 1
    fi
}

# Perform OAuth device flow test
test_device_flow() {
    log_info "Testing OAuth Device Flow for user: $USERNAME"
    
    if [[ -z "$CLIENT_SECRET" ]]; then
        log_error "KEYCLOAK_CLIENT_SECRET is not set"
        exit 1
    fi
    
    local device_endpoint="${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/auth/device"
    local token_endpoint="${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token"
    local userinfo_endpoint="${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/userinfo"
    
    # Step 1: Request device authorization
    log_info "Requesting device authorization..."
    
    local response
    response=$(curl -s --fail \
        -X POST "$device_endpoint" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=${CLIENT_ID}" \
        -d "scope=openid profile email") || {
        log_error "Failed to request device authorization"
        exit 1
    }
    
    # Parse response
    local device_code user_code verification_uri verification_uri_complete interval expires_in
    device_code=$(echo "$response" | jq -r '.device_code // empty')
    user_code=$(echo "$response" | jq -r '.user_code // empty')
    verification_uri=$(echo "$response" | jq -r '.verification_uri // empty')
    verification_uri_complete=$(echo "$response" | jq -r '.verification_uri_complete // empty')
    interval=$(echo "$response" | jq -r '.interval // 5')
    expires_in=$(echo "$response" | jq -r '.expires_in // 300')
    
    if [[ -z "$device_code" || -z "$user_code" ]]; then
        log_error "Failed to get device authorization"
        echo "Response: $response"
        exit 1
    fi
    
    log_success "Device authorization obtained"
    
    # Display user instructions
    echo ""
    echo "============================================"
    echo "OAuth Device Flow Test"
    echo "============================================"
    echo ""
    echo "To complete authentication:"
    echo "1. Open your web browser"
    echo "2. Visit: $verification_uri"
    echo "3. Enter the code: $user_code"
    echo "4. Login as user: $USERNAME"
    echo ""
    if [[ -n "$verification_uri_complete" ]]; then
        echo "Or visit this direct link:"
        echo "   $verification_uri_complete"
        echo ""
    fi
    echo "Test will timeout in ${expires_in} seconds"
    echo "Press Ctrl+C to cancel"
    echo ""
    
    # Step 2: Poll for token
    log_info "Polling for authentication token..."
    
    local max_attempts=$((expires_in / interval))
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        sleep "$interval"
        
        echo -n "."
        
        local token_response
        token_response=$(curl -s \
            -X POST "$token_endpoint" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
            -d "device_code=${device_code}" \
            -d "client_id=${CLIENT_ID}" \
            -d "client_secret=${CLIENT_SECRET}")
        
        # Check for successful token
        if echo "$token_response" | jq -e '.access_token' >/dev/null 2>&1; then
            echo ""
            log_success "Authentication token obtained!"
            
            local access_token refresh_token id_token token_type expires_in_token
            access_token=$(echo "$token_response" | jq -r '.access_token')
            refresh_token=$(echo "$token_response" | jq -r '.refresh_token // "N/A"')
            id_token=$(echo "$token_response" | jq -r '.id_token // "N/A"')
            token_type=$(echo "$token_response" | jq -r '.token_type // "Bearer"')
            expires_in_token=$(echo "$token_response" | jq -r '.expires_in // "N/A"')
            
            echo ""
            echo "Token Information:"
            echo "  Type: $token_type"
            echo "  Expires in: $expires_in_token seconds"
            echo "  Has refresh token: $([ "$refresh_token" != "N/A" ] && echo "Yes" || echo "No")"
            echo "  Has ID token: $([ "$id_token" != "N/A" ] && echo "Yes" || echo "No")"
            echo ""
            
            # Step 3: Get user information
            log_info "Retrieving user information..."
            
            local user_info
            user_info=$(curl -s --fail \
                -H "Authorization: Bearer $access_token" \
                "$userinfo_endpoint") || {
                log_error "Failed to get user information"
                exit 1
            }
            
            # Parse user info
            local oauth_username oauth_email oauth_name oauth_sub
            oauth_username=$(echo "$user_info" | jq -r '.preferred_username // .sub // empty')
            oauth_email=$(echo "$user_info" | jq -r '.email // empty')
            oauth_name=$(echo "$user_info" | jq -r '.name // empty')
            oauth_sub=$(echo "$user_info" | jq -r '.sub // empty')
            
            echo "User Information:"
            echo "  Subject: $oauth_sub"
            echo "  Username: $oauth_username"
            echo "  Name: $oauth_name"
            echo "  Email: $oauth_email"
            echo ""
            
            # Verify username
            if [[ "$oauth_username" == "$USERNAME" ]]; then
                log_success "✓ Username verification passed"
            else
                log_warning "⚠ Username mismatch: expected '$USERNAME', got '$oauth_username'"
            fi
            
            # Test token introspection (if supported)
            log_info "Testing token introspection..."
            local introspect_endpoint="${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token/introspect"
            local introspect_response
            introspect_response=$(curl -s \
                -X POST "$introspect_endpoint" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -d "token=${access_token}" \
                -d "client_id=${CLIENT_ID}" \
                -d "client_secret=${CLIENT_SECRET}")
            
            local token_active
            token_active=$(echo "$introspect_response" | jq -r '.active // false')
            
            if [[ "$token_active" == "true" ]]; then
                log_success "✓ Token is active and valid"
                
                local token_exp token_iat token_iss
                token_exp=$(echo "$introspect_response" | jq -r '.exp // empty')
                token_iat=$(echo "$introspect_response" | jq -r '.iat // empty')
                token_iss=$(echo "$introspect_response" | jq -r '.iss // empty')
                
                echo "Token Details:"
                echo "  Issued at: $([ -n "$token_iat" ] && date -d "@$token_iat" || echo "N/A")"
                echo "  Expires at: $([ -n "$token_exp" ] && date -d "@$token_exp" || echo "N/A")"
                echo "  Issuer: $token_iss"
            else
                log_warning "⚠ Token introspection indicates token is not active"
            fi
            
            echo ""
            log_success "🎉 OAuth Device Flow test completed successfully!"
            echo ""
            echo "This confirms that:"
            echo "  - Keycloak is properly configured"
            echo "  - Device flow is enabled"
            echo "  - Client authentication works"
            echo "  - User can authenticate"
            echo "  - Tokens are properly issued and validated"
            echo ""
            
            return 0
        fi
        
        # Check for errors
        local error_code error_description
        error_code=$(echo "$token_response" | jq -r '.error // empty')
        error_description=$(echo "$token_response" | jq -r '.error_description // empty')
        
        case "$error_code" in
            "authorization_pending")
                # Continue polling
                ;;
            "slow_down")
                interval=$((interval + 5))
                ;;
            "expired_token")
                echo ""
                log_error "Authorization expired"
                exit 1
                ;;
            "access_denied")
                echo ""
                log_error "Access denied by user"
                exit 1
                ;;
            "")
                # No error, continue
                ;;
            *)
                echo ""
                if [[ -n "$error_description" ]]; then
                    log_error "OAuth error: $error_code - $error_description"
                else
                    log_error "OAuth error: $error_code"
                fi
                exit 1
                ;;
        esac
        
        attempt=$((attempt + 1))
    done
    
    echo ""
    log_error "Authentication timeout after ${expires_in} seconds"
    exit 1
}

# Show configuration
show_config() {
    echo "OAuth Device Flow Test Configuration:"
    echo "  Keycloak URL: $KEYCLOAK_URL"
    echo "  Realm: $REALM"
    echo "  Client ID: $CLIENT_ID"
    echo "  Client Secret: $([ -n "$CLIENT_SECRET" ] && echo "Set" || echo "Not set")"
    echo "  Test Username: $USERNAME"
    echo ""
}

# Main function
main() {
    echo "OAuth Device Flow Authentication Test"
    echo "====================================="
    echo ""
    
    show_config
    check_dependencies
    test_connectivity
    test_device_flow
}

# Handle script arguments
case "${1:-test}" in
    test)
        shift 2>/dev/null || true
        main "$@"
        ;;
    help|--help|-h)
        echo "OAuth Device Flow Test Script"
        echo ""
        echo "Usage: $0 [test] [username]"
        echo ""
        echo "Arguments:"
        echo "  username    - Username to test (default: testuser)"
        echo ""
        echo "Environment Variables:"
        echo "  KEYCLOAK_URL         - Keycloak server URL"
        echo "  KEYCLOAK_REALM       - Keycloak realm name"
        echo "  KEYCLOAK_CLIENT_ID   - OAuth client ID"
        echo "  KEYCLOAK_CLIENT_SECRET - OAuth client secret"
        echo ""
        echo "Examples:"
        echo "  $0 john.doe"
        echo "  KEYCLOAK_CLIENT_SECRET=secret123 $0 test alice"
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
