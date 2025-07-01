#!/bin/bash
set -e

echo "=== Keycloak Device Flow Test Script ==="

# Configuration
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
REALM="${KEYCLOAK_REALM:-hybrid-auth}"
CLIENT_ID="${CLIENT_ID:-device-flow-client}"
CLIENT_SECRET="${CLIENT_SECRET:-}"

# Keycloak endpoints
DEVICE_ENDPOINT="${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/auth/device"
TOKEN_ENDPOINT="${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token"
USERINFO_ENDPOINT="${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/userinfo"

echo "🚀 Configuration:"
echo "   Keycloak URL: ${KEYCLOAK_URL}"
echo "   Realm: ${REALM}"
echo "   Client ID: ${CLIENT_ID}"
echo "   Client Secret: ${CLIENT_SECRET:+[SET]}${CLIENT_SECRET:-[NOT SET]}"
echo ""

# Function to make HTTP requests
make_request() {
    local method="$1"
    local url="$2"
    local data="$3"
    local headers="$4"
    
    if [ -n "$data" ]; then
        curl -s -X "$method" "$url" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            ${headers:+-H "$headers"} \
            -d "$data"
    else
        curl -s -X "$method" "$url" \
            ${headers:+-H "$headers"}
    fi
}

# Step 1: Initiate device authorization
echo "🔐 Step 1: Initiating device authorization..."

DEVICE_DATA="client_id=${CLIENT_ID}&scope=openid profile email"
DEVICE_RESPONSE=$(make_request "POST" "$DEVICE_ENDPOINT" "$DEVICE_DATA")

# Check if response is valid JSON
if ! echo "$DEVICE_RESPONSE" | jq . >/dev/null 2>&1; then
    echo "❌ Invalid response from device endpoint:"
    echo "$DEVICE_RESPONSE"
    exit 1
fi

# Extract values from response
DEVICE_CODE=$(echo "$DEVICE_RESPONSE" | jq -r '.device_code')
USER_CODE=$(echo "$DEVICE_RESPONSE" | jq -r '.user_code')
VERIFICATION_URI=$(echo "$DEVICE_RESPONSE" | jq -r '.verification_uri')
VERIFICATION_URI_COMPLETE=$(echo "$DEVICE_RESPONSE" | jq -r '.verification_uri_complete')
EXPIRES_IN=$(echo "$DEVICE_RESPONSE" | jq -r '.expires_in')
INTERVAL=$(echo "$DEVICE_RESPONSE" | jq -r '.interval')

if [ "$DEVICE_CODE" = "null" ]; then
    echo "❌ Failed to get device code:"
    echo "$DEVICE_RESPONSE" | jq .
    exit 1
fi

echo "✅ Device authorization initiated!"
echo "   Device Code: ${DEVICE_CODE}"
echo "   User Code: ${USER_CODE}"
echo "   Verification URI: ${VERIFICATION_URI}"
echo "   Complete URI: ${VERIFICATION_URI_COMPLETE}"
echo "   Expires in: ${EXPIRES_IN} seconds"
echo "   Polling interval: ${INTERVAL} seconds"
echo ""

echo "👤 User Instructions:"
echo "   1. Open: ${VERIFICATION_URI}"
echo "   2. Enter code: ${USER_CODE}"
echo "   3. Sign in with your Keycloak credentials"
echo ""
echo "🔗 Quick link (copy and paste):"
echo "   ${VERIFICATION_URI_COMPLETE}"
echo ""

# Step 2: Poll for authorization
echo "⏳ Step 2: Polling for user authorization..."
echo "Press Ctrl+C to cancel"
echo ""

TOKEN_DATA="grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=${DEVICE_CODE}&client_id=${CLIENT_ID}"
if [ -n "$CLIENT_SECRET" ]; then
    TOKEN_DATA="${TOKEN_DATA}&client_secret=${CLIENT_SECRET}"
fi

ATTEMPTS=0
MAX_ATTEMPTS=$((EXPIRES_IN / INTERVAL))

while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    TOKEN_RESPONSE=$(make_request "POST" "$TOKEN_ENDPOINT" "$TOKEN_DATA")
    
    # Check if we got an access token
    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
    if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
        echo ""
        echo "✅ Authorization successful!"
        break
    fi
    
    # Check for errors
    ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error // empty')
    case "$ERROR" in
        "authorization_pending")
            printf "."
            sleep "$INTERVAL"
            ATTEMPTS=$((ATTEMPTS + 1))
            ;;
        "slow_down")
            echo ""
            echo "⚠️  Slowing down polling..."
            sleep $((INTERVAL + 5))
            ;;
        "access_denied")
            echo ""
            echo "❌ User denied authorization"
            exit 1
            ;;
        "expired_token")
            echo ""
            echo "❌ Device code expired"
            exit 1
            ;;
        *)
            echo ""
            echo "❌ Unknown error:"
            echo "$TOKEN_RESPONSE" | jq .
            exit 1
            ;;
    esac
done

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo ""
    echo "❌ Authorization timed out"
    exit 1
fi

# Display token information
echo ""
echo "🎉 Token Response:"
TOKEN_TYPE=$(echo "$TOKEN_RESPONSE" | jq -r '.token_type')
EXPIRES_IN_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_in')
REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token // empty')
ID_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.id_token // empty')

echo "   Access Token: ${ACCESS_TOKEN:0:50}..."
echo "   Token Type: ${TOKEN_TYPE}"
echo "   Expires In: ${EXPIRES_IN_TOKEN} seconds"
echo "   Refresh Token: ${REFRESH_TOKEN:+Present}${REFRESH_TOKEN:-Not provided}"
echo "   ID Token: ${ID_TOKEN:+Present}${ID_TOKEN:-Not provided}"
echo ""

# Step 3: Get user information
echo "👤 Step 3: Getting user information..."

USER_INFO=$(make_request "GET" "$USERINFO_ENDPOINT" "" "Authorization: Bearer $ACCESS_TOKEN")

if echo "$USER_INFO" | jq . >/dev/null 2>&1; then
    echo "✅ User Information:"
    
    USERNAME=$(echo "$USER_INFO" | jq -r '.preferred_username // .sub')
    EMAIL=$(echo "$USER_INFO" | jq -r '.email // "Not provided"')
    NAME=$(echo "$USER_INFO" | jq -r '.name // "Not provided"')
    SUB=$(echo "$USER_INFO" | jq -r '.sub')
    
    echo "   Username: ${USERNAME}"
    echo "   Email: ${EMAIL}"
    echo "   Name: ${NAME}"
    echo "   Subject: ${SUB}"
else
    echo "❌ Failed to get user information:"
    echo "$USER_INFO"
fi

echo ""
echo "🎊 Device flow completed successfully!"

# Show detailed information if requested
if [ "$1" = "--verbose" ] || [ "$1" = "-v" ]; then
    echo ""
    echo "🔍 Full Token Response:"
    echo "$TOKEN_RESPONSE" | jq .
    echo ""
    echo "🔍 Full User Info:"
    echo "$USER_INFO" | jq .
fi

echo ""
echo "💡 Next steps:"
echo "   - Use the access token to make authenticated API calls"
echo "   - Implement token refresh using the refresh token"
echo "   - Store tokens securely in your application"
