#!/bin/bash
# OAuth Device Flow Authentication Script for PAM
# This script handles OAuth authentication via device flow for SSH/PAM login

set -euo pipefail

# Configuration - these can be overridden by environment variables
KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak:8080}"
REALM="${KEYCLOAK_REALM:-hybrid-auth}"
CLIENT_ID="${KEYCLOAK_CLIENT_ID:-ssh-pam-client}"
CLIENT_SECRET="${KEYCLOAK_CLIENT_SECRET:-}"
TIMEOUT="${OAUTH_TIMEOUT:-300}"
POLL_INTERVAL="${OAUTH_POLL_INTERVAL:-5}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Error function
error() {
    log "ERROR: $*"
    exit 1
}

# Check dependencies
check_dependencies() {
    command -v curl >/dev/null 2>&1 || error "curl is required but not installed"
    command -v jq >/dev/null 2>&1 || error "jq is required but not installed"
}

# Validate configuration
validate_config() {
    [[ -n "$KEYCLOAK_URL" ]] || error "KEYCLOAK_URL is not set"
    [[ -n "$REALM" ]] || error "KEYCLOAK_REALM is not set"
    [[ -n "$CLIENT_ID" ]] || error "KEYCLOAK_CLIENT_ID is not set"
    [[ -n "$CLIENT_SECRET" ]] || error "KEYCLOAK_CLIENT_SECRET is not set"
}

# Test Keycloak connectivity
test_connectivity() {
    local health_url="${KEYCLOAK_URL}/realms/${REALM}"
    
    if ! curl -s --connect-timeout 10 --max-time 30 "$health_url" >/dev/null; then
        error "Cannot connect to Keycloak at $health_url"
    fi
    
    log "Successfully connected to Keycloak"
}

# Perform OAuth device flow authentication
oauth_device_flow() {
    local username="$1"
    local device_endpoint="${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/auth/device"
    local token_endpoint="${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token"
    local userinfo_endpoint="${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/userinfo"
    
    log "Starting OAuth device flow for user: $username"
    
    # Step 1: Request device and user codes
    log "Requesting device authorization..."
    local response
    response=$(curl -s --fail \
        -X POST "$device_endpoint" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=${CLIENT_ID}" \
        -d "scope=openid profile email") || error "Failed to request device authorization"
    
    # Parse device flow response
    local device_code user_code verification_uri verification_uri_complete interval expires_in
    device_code=$(echo "$response" | jq -r '.device_code // empty')
    user_code=$(echo "$response" | jq -r '.user_code // empty')
    verification_uri=$(echo "$response" | jq -r '.verification_uri // empty')
    verification_uri_complete=$(echo "$response" | jq -r '.verification_uri_complete // empty')
    interval=$(echo "$response" | jq -r '.interval // 5')
    expires_in=$(echo "$response" | jq -r '.expires_in // 300')
    
    [[ -n "$device_code" ]] || error "Failed to get device code"
    [[ -n "$user_code" ]] || error "Failed to get user code"
    [[ -n "$verification_uri" ]] || error "Failed to get verification URI"
    
    log "Device authorization successful"
    
    # Step 2: Display instructions to user
    echo ""
    echo "============================================"
    echo "OAuth Device Flow Authentication Required"
    echo "============================================"
    echo ""
    echo "To complete your login, please:"
    echo "1. Open your web browser"
    echo "2. Visit: $verification_uri"
    echo "3. Enter the code: $user_code"
    echo ""
    if [[ -n "$verification_uri_complete" ]]; then
        echo "Or visit this direct link:"
        echo "   $verification_uri_complete"
        echo ""
    fi
    echo "Waiting for authentication... (timeout in ${expires_in}s)"
    echo "Press Ctrl+C to cancel"
    echo ""
    
    # Step 3: Poll for token
    local max_attempts=$((expires_in / interval))
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        sleep "$interval"
        
        log "Polling for token (attempt $((attempt + 1))/$max_attempts)..."
        
        local token_response
        token_response=$(curl -s \
            -X POST "$token_endpoint" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
            -d "device_code=${device_code}" \
            -d "client_id=${CLIENT_ID}" \
            -d "client_secret=${CLIENT_SECRET}")
        
        # Check for successful token response
        if echo "$token_response" | jq -e '.access_token' >/dev/null 2>&1; then
            local access_token
            access_token=$(echo "$token_response" | jq -r '.access_token')
            
            log "Token obtained successfully"
            
            # Step 4: Verify user identity
            log "Verifying user identity..."
            local user_info
            user_info=$(curl -s --fail \
                -H "Authorization: Bearer $access_token" \
                "$userinfo_endpoint") || error "Failed to get user info"
            
            local oauth_username oauth_email oauth_name
            oauth_username=$(echo "$user_info" | jq -r '.preferred_username // .sub // empty')
            oauth_email=$(echo "$user_info" | jq -r '.email // empty')
            oauth_name=$(echo "$user_info" | jq -r '.name // empty')
            
            [[ -n "$oauth_username" ]] || error "Could not determine username from OAuth response"
            
            # Verify username matches
            if [[ "$oauth_username" == "$username" ]]; then
                echo ""
                echo "✓ Authentication successful!"
                echo "  User: $oauth_name ($oauth_username)"
                [[ -n "$oauth_email" ]] && echo "  Email: $oauth_email"
                echo ""
                
                # Create/update user account if needed
                create_user_account "$oauth_username" "$oauth_name" "$oauth_email"
                
                log "Authentication completed successfully for $username"
                return 0
            else
                error "Username mismatch: expected '$username', but OAuth user is '$oauth_username'"
            fi
        fi
        
        # Check for errors
        local error_code error_description
        error_code=$(echo "$token_response" | jq -r '.error // empty')
        error_description=$(echo "$token_response" | jq -r '.error_description // empty')
        
        case "$error_code" in
            "authorization_pending")
                log "Authorization pending, continuing to poll..."
                ;;
            "slow_down")
                log "Slow down requested, increasing interval..."
                interval=$((interval + 5))
                ;;
            "expired_token")
                error "Authorization expired. Please try again."
                ;;
            "access_denied")
                error "Access denied by user"
                ;;
            "")
                # No error field, but no token either - continue polling
                ;;
            *)
                if [[ -n "$error_description" ]]; then
                    error "OAuth error: $error_code - $error_description"
                else
                    error "OAuth error: $error_code"
                fi
                ;;
        esac
        
        attempt=$((attempt + 1))
    done
    
    error "Authentication timeout after ${expires_in} seconds"
}

# Create or update user account
create_user_account() {
    local username="$1"
    local display_name="$2"
    local email="$3"
    
    # Check if user already exists
    if id "$username" >/dev/null 2>&1; then
        log "User account already exists: $username"
        return 0
    fi
    
    log "Creating user account: $username"
    
    # Create user with home directory
    if useradd -m -s /bin/bash -c "${display_name:-$username}" "$username"; then
        log "Successfully created user account: $username"
        
        # Set up basic home directory structure
        local home_dir="/home/$username"
        
        # Copy skeleton files
        cp -r /etc/skel/. "$home_dir/" 2>/dev/null || true
        
        # Set proper ownership
        chown -R "$username:$username" "$home_dir"
        chmod 755 "$home_dir"
        
        # Create a welcome message
        cat > "$home_dir/.oauth_welcome" << EOF
Welcome to the OAuth-authenticated SSH session!

User Information:
- Username: $username
- Display Name: ${display_name:-$username}
- Email: ${email:-"Not provided"}
- Authentication: OAuth via Keycloak
- Session Started: $(date)

This account was created automatically via OAuth authentication.
EOF
        chown "$username:$username" "$home_dir/.oauth_welcome"
        
        log "User account setup completed: $username"
    else
        log "WARNING: Failed to create user account for $username"
    fi
}

# Main execution
main() {
    # Only run for auth requests
    if [[ "${PAM_TYPE:-}" != "auth" ]]; then
        log "Not an auth request (PAM_TYPE=${PAM_TYPE:-}), skipping OAuth"
        exit 0
    fi
    
    local username="${PAM_USER:-}"
    [[ -n "$username" ]] || error "PAM_USER not set"
    
    log "OAuth authentication requested for user: $username"
    
    # Perform checks
    check_dependencies
    validate_config
    test_connectivity
    
    # Perform authentication
    oauth_device_flow "$username"
}

# Execute main function
main "$@"
