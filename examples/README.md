# Keycloak Configuration Examples

This directory contains example configurations and test scripts for Keycloak OAuth flows.

## Files

### Configuration Guides
- `../docs/keycloak-setup-guide.md` - Complete step-by-step setup guide

### Test Scripts
- `test-device-flow.sh` - Bash script to test OAuth 2.0 Device Authorization Grant
- `test-device-flow.js` - Node.js script for device flow testing

## Quick Start

### 1. Set up Keycloak Realm

Follow the guide in `../docs/keycloak-setup-guide.md` to:
- Create a new realm
- Enable device flow
- Create an OAuth client
- Add test users

### 2. Test Device Flow

**Using Bash (requires jq and curl):**
```bash
# Basic test
./test-device-flow.sh

# With verbose output
./test-device-flow.sh --verbose

# With custom configuration
KEYCLOAK_URL=http://192.168.1.103:8080 \
KEYCLOAK_REALM=my-realm \
CLIENT_ID=my-client \
CLIENT_SECRET=my-secret \
./test-device-flow.sh
```

**Using Node.js:**
```bash
# Install dependencies (optional - uses only Node.js built-ins)
npm install

# Basic test
node test-device-flow.js

# With verbose output
node test-device-flow.js --verbose

# With custom configuration
KEYCLOAK_URL=http://192.168.1.103:8080 \
CLIENT_SECRET=your-secret \
node test-device-flow.js
```

## Environment Variables

Both scripts support these environment variables:

- `KEYCLOAK_URL` - Base URL of Keycloak (default: http://localhost:8080)
- `KEYCLOAK_REALM` - Realm name (default: hybrid-auth)
- `CLIENT_ID` - OAuth client ID (default: device-flow-client)
- `CLIENT_SECRET` - OAuth client secret (required for confidential clients)

## Expected Flow

1. **Script starts device authorization**
   - Makes request to device authorization endpoint
   - Receives device code and user code

2. **User verification**
   - Script displays verification URL and user code
   - User opens URL in browser
   - User enters code and signs in

3. **Script polls for authorization**
   - Continuously checks if user has authorized
   - Receives access token when complete

4. **User information retrieval**
   - Uses access token to get user profile
   - Displays user information

## Troubleshooting

### Common Issues

**"jq: command not found"**
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq
```

**"Connection refused"**
- Check Keycloak is running: `../network-info.sh`
- Verify the KEYCLOAK_URL is correct
- Check firewall settings

**"Invalid client" error**
- Verify realm exists
- Check client ID is correct
- Ensure client is enabled

**"Device flow not supported"**
- Enable device flow in Realm Settings → Advanced
- Enable "Device authorization grant" in client settings

**"User code expired"**
- Default expiration is 10 minutes
- Restart the script to get a new code

### Debug Mode

Run with verbose output to see full API responses:
```bash
./test-device-flow.sh --verbose
node test-device-flow.js --verbose
```

## Integration Examples

### Python Example
```python
import requests
import time
import json

# Device authorization
response = requests.post(f"{KEYCLOAK_URL}/realms/{REALM}/protocol/openid-connect/auth/device", {
    'client_id': CLIENT_ID,
    'scope': 'openid profile email'
})
device_auth = response.json()

print(f"Go to: {device_auth['verification_uri']}")
print(f"Enter code: {device_auth['user_code']}")

# Poll for token
while True:
    response = requests.post(f"{KEYCLOAK_URL}/realms/{REALM}/protocol/openid-connect/token", {
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        'device_code': device_auth['device_code'],
        'client_id': CLIENT_ID
    })
    
    if response.status_code == 200:
        tokens = response.json()
        break
    
    time.sleep(device_auth['interval'])
```

### curl Example
```bash
# 1. Start device flow
RESPONSE=$(curl -s -X POST \
  "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/auth/device" \
  -d "client_id=${CLIENT_ID}&scope=openid profile email")

USER_CODE=$(echo "$RESPONSE" | jq -r '.user_code')
DEVICE_CODE=$(echo "$RESPONSE" | jq -r '.device_code')

echo "Visit: $(echo "$RESPONSE" | jq -r '.verification_uri')"
echo "Enter: $USER_CODE"

# 2. Poll for token
curl -s -X POST \
  "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=${DEVICE_CODE}&client_id=${CLIENT_ID}"
```
