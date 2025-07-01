#!/bin/bash
# Demo OAuth Device Flow
# This script demonstrates the OAuth Device Flow process

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
CLIENT_ID="ssh-pam-client"
CLIENT_SECRET="ssh-pam-client-secret-2024-hybrid-auth-lab"
KEYCLOAK_URL="http://localhost:8080"
REALM="hybrid-auth"

echo -e "${BLUE}=== OAuth Device Flow Demo ===${NC}"
echo ""

# Step 1: Request device authorization
echo -e "${BLUE}Step 1: Requesting device authorization...${NC}"
DEVICE_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" \
    "$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/auth/device")

# Extract values
DEVICE_CODE=$(echo "$DEVICE_RESPONSE" | jq -r '.device_code')
USER_CODE=$(echo "$DEVICE_RESPONSE" | jq -r '.user_code')
VERIFICATION_URI_COMPLETE=$(echo "$DEVICE_RESPONSE" | jq -r '.verification_uri_complete')
EXPIRES_IN=$(echo "$DEVICE_RESPONSE" | jq -r '.expires_in')
INTERVAL=$(echo "$DEVICE_RESPONSE" | jq -r '.interval')

echo -e "${GREEN}Device authorization successful!${NC}"
echo ""
echo -e "${YELLOW}User Code: $USER_CODE${NC}"
echo -e "${YELLOW}Verification URL: $VERIFICATION_URI_COMPLETE${NC}"
echo "Expires in: $EXPIRES_IN seconds"
echo ""

# Step 2: Open browser (if available)
if command -v xdg-open >/dev/null 2>&1; then
    echo -e "${BLUE}Opening browser to verification URL...${NC}"
    xdg-open "$VERIFICATION_URI_COMPLETE" 2>/dev/null || true
elif command -v open >/dev/null 2>&1; then
    echo -e "${BLUE}Opening browser to verification URL...${NC}"
    open "$VERIFICATION_URI_COMPLETE" 2>/dev/null || true
else
    echo -e "${YELLOW}Please open this URL in your browser:${NC}"
    echo "$VERIFICATION_URI_COMPLETE"
fi

echo ""
echo -e "${BLUE}Step 2: Please complete the authentication in your browser${NC}"
echo "Login with: admin/admin or testuser/testpass"
echo ""

# Step 3: Poll for token
echo -e "${BLUE}Step 3: Polling for authorization token...${NC}"
echo "Waiting for user to complete authentication..."

MAX_ATTEMPTS=$((EXPIRES_IN / INTERVAL))
ATTEMPT=0

while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
    TOKEN_RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=$DEVICE_CODE&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" \
        "$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/token")
    
    if echo "$TOKEN_RESPONSE" | jq -e '.access_token' >/dev/null 2>&1; then
        echo ""
        echo -e "${GREEN}✓ Authentication successful!${NC}"
        
        ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
        REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token')
        TOKEN_TYPE=$(echo "$TOKEN_RESPONSE" | jq -r '.token_type')
        
        echo "Token Type: $TOKEN_TYPE"
        echo "Access Token (first 50 chars): ${ACCESS_TOKEN:0:50}..."
        echo ""
        
        # Decode and show token info
        echo -e "${BLUE}Token Information:${NC}"
        echo "$ACCESS_TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq '.' || echo "Could not decode token payload"
        echo ""
        echo -e "${GREEN}OAuth Device Flow completed successfully!${NC}"
        exit 0
    fi
    
    ERROR_CODE=$(echo "$TOKEN_RESPONSE" | jq -r '.error // empty')
    if [[ "$ERROR_CODE" == "authorization_pending" ]]; then
        echo -n "."
        sleep "$INTERVAL"
        ATTEMPT=$((ATTEMPT + 1))
    elif [[ "$ERROR_CODE" == "slow_down" ]]; then
        echo -n "s"
        sleep $((INTERVAL + 5))
        ATTEMPT=$((ATTEMPT + 1))
    else
        echo ""
        echo -e "${YELLOW}Error or timeout occurred:${NC}"
        echo "$TOKEN_RESPONSE" | jq '.'
        exit 1
    fi
done

echo ""
echo -e "${YELLOW}Timeout reached. Please try again.${NC}"
