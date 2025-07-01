# Tutorial: OAuth/PAM Integration for SSH Authentication

This tutorial demonstrates how to implement OAuth 2.0 Device Flow authentication for SSH using Linux PAM (Pluggable Authentication Modules). You'll learn how to bridge modern identity providers with traditional Linux services.

## What You'll Build

By the end of this tutorial, you'll have:
- SSH authentication that uses OAuth instead of local passwords
- Users who authenticate via browser-based OAuth flow
- Integration between Keycloak (OAuth server) and Linux PAM
- A foundation for modernizing traditional Linux authentication

## Learning Objectives

- Understand how PAM enables pluggable authentication
- Learn OAuth 2.0 Device Flow for headless authentication
- Implement custom PAM modules for OAuth integration
- Configure SSH to use OAuth authentication
- Debug and troubleshoot OAuth/PAM integration

## Tutorial Architecture

```
SSH User Login
       ↓
   SSH Server (sshd)
       ↓
   PAM Authentication Stack
       ↓
   Custom OAuth PAM Module
       ↓
   OAuth Device Flow
       ↓ 
   Keycloak (OAuth Server)
       ↓
   User Browser Authentication
       ↓
   SSH Session Granted
```

## Understanding Linux PAM

PAM (Pluggable Authentication Modules) allows you to configure how authentication works without modifying applications like SSH.

### PAM Configuration Structure

```bash
# /etc/pam.d/sshd - SSH PAM configuration
auth    required    pam_env.so
auth    required    pam_exec.so    /opt/auth/oauth_auth.sh
auth    include     common-auth
account include     common-account
session include     common-session
```

**PAM Module Types:**
- `auth`: Authentication (verify user identity)
- `account`: Account validation (user allowed to login?)
- `session`: Session management (setup user environment)
- `password`: Password changing

**PAM Control Flags:**
- `required`: Must succeed, but continue processing
- `requisite`: Must succeed, stop if fails
- `sufficient`: If succeeds, skip remaining modules
- `optional`: Success/failure doesn't affect result

## Tutorial Prerequisites

This tutorial assumes:
- Basic understanding of Linux authentication
- Familiarity with SSH and command line
- Understanding of OAuth 2.0 concepts (optional but helpful)

**Lab Environment:**
- Keycloak OAuth server running on port 8080
- Ubuntu SSH server with PAM support
- Pre-configured OAuth client credentials

## Step 1: Understanding the Existing Setup

Let's explore what's already configured in the tutorial environment:

```bash
# Connect to the Ubuntu SSH container
docker exec -it ubuntu-sshd-client bash

# Examine the current PAM configuration for SSH
cat /etc/pam.d/sshd

# Look at the OAuth configuration
cat /etc/default/oauth-auth

# Check the OAuth authentication script
ls -la /opt/auth/oauth_auth.sh
```

**What you'll see:**
- SSH PAM configuration that includes OAuth module
- OAuth client credentials and endpoints
- Custom authentication script for device flow

## Step 2: How OAuth PAM Integration Works

### The Authentication Flow

1. **User initiates SSH**: `ssh testuser@localhost -p 2222`
2. **SSH calls PAM**: sshd consults `/etc/pam.d/sshd`
3. **PAM calls OAuth script**: `pam_exec.so` executes `/opt/auth/oauth_auth.sh`
4. **Script requests device code**: Makes API call to Keycloak
5. **User sees device code**: Script displays code and verification URL
6. **User completes browser auth**: Visits URL, enters code, authenticates
7. **Script polls for token**: Checks if user completed authentication
8. **SSH session granted**: On successful OAuth, SSH access is granted

### Examining the OAuth Script

```bash
# View the OAuth authentication script
cat /opt/auth/oauth_auth.sh | head -50
```

**Key functions in the script:**
- `check_dependencies()`: Ensures curl and jq are available
- `request_device_authorization()`: Initiates OAuth device flow
- `poll_for_token()`: Waits for user to complete authentication
- `validate_user()`: Checks if OAuth user matches SSH user

## Step 2: Configure Keycloak Client for SSH/PAM

In Keycloak admin console:

1. **Create a new client:**
   - Client ID: `ssh-pam-client`
   - Client Protocol: `openid-connect`
   - Access Type: `confidential`

2. **Configure client settings:**
   - Standard Flow Enabled: `ON`
   - Implicit Flow Enabled: `OFF`
   - Direct Access Grants Enabled: `ON`
   - OAuth 2.0 Device Authorization Grant Enabled: `ON`
   - Service Accounts Enabled: `ON`

3. **Set Valid Redirect URIs:**
   ```
   http://localhost:*
   urn:ietf:wg:oauth:2.0:oob
   ```

4. **Note the client secret** from the Credentials tab

## Step 3: Configure SSSD for OAuth

Copy and customize the SSSD configuration:

```bash
# Copy the OAuth SSSD configuration template
cp /opt/config/sssd-oauth.conf.sample /etc/sssd/sssd.conf

# Update the client secret
sed -i 's/YOUR_CLIENT_SECRET_HERE/actual_client_secret_from_keycloak/' /etc/sssd/sssd.conf

# Set proper permissions
chmod 600 /etc/sssd/sssd.conf
chown root:root /etc/sssd/sssd.conf
```

## Step 4: Configure PAM for OAuth Authentication

### Option A: Using pam_exec with Custom OAuth Script

Create a custom OAuth authentication script:

```bash
# Create the OAuth PAM script directory
mkdir -p /opt/auth

# Create the OAuth authentication script
cat > /opt/auth/oauth_auth.sh << 'EOF'
#!/bin/bash
# OAuth Device Flow Authentication Script for PAM

# Configuration
KEYCLOAK_URL="http://keycloak:8080"
REALM="hybrid-auth"
CLIENT_ID="ssh-pam-client"
CLIENT_SECRET="${PAM_OAUTH_CLIENT_SECRET}"

# Function to perform device flow authentication
oauth_device_flow() {
    local username="$1"
    
    # Request device and user codes
    response=$(curl -s -X POST \
        "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/auth/device" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=${CLIENT_ID}")
    
    if [ $? -ne 0 ]; then
        echo "Failed to contact authentication server" >&2
        return 1
    fi
    
    # Parse response
    device_code=$(echo "$response" | jq -r '.device_code // empty')
    user_code=$(echo "$response" | jq -r '.user_code // empty')
    verification_uri=$(echo "$response" | jq -r '.verification_uri // empty')
    verification_uri_complete=$(echo "$response" | jq -r '.verification_uri_complete // empty')
    interval=$(echo "$response" | jq -r '.interval // 5')
    
    if [ -z "$device_code" ] || [ -z "$user_code" ]; then
        echo "Failed to get device authorization" >&2
        return 1
    fi
    
    # Display instructions to user
    echo "To complete authentication, please visit:"
    echo "  $verification_uri"
    echo "And enter the code: $user_code"
    echo ""
    echo "Or visit directly: $verification_uri_complete"
    echo ""
    echo "Waiting for authentication..."
    
    # Poll for token
    max_attempts=30
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        sleep $interval
        
        token_response=$(curl -s -X POST \
            "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
            -d "device_code=${device_code}" \
            -d "client_id=${CLIENT_ID}" \
            -d "client_secret=${CLIENT_SECRET}")
        
        if echo "$token_response" | jq -e '.access_token' > /dev/null; then
            # Success - verify token and user
            access_token=$(echo "$token_response" | jq -r '.access_token')
            
            # Get user info
            user_info=$(curl -s -H "Authorization: Bearer $access_token" \
                "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/userinfo")
            
            oauth_username=$(echo "$user_info" | jq -r '.preferred_username // empty')
            
            if [ "$oauth_username" = "$username" ]; then
                echo "Authentication successful for user: $username" >&2
                return 0
            else
                echo "Username mismatch: expected $username, got $oauth_username" >&2
                return 1
            fi
        fi
        
        # Check for errors
        error=$(echo "$token_response" | jq -r '.error // empty')
        if [ "$error" = "authorization_pending" ]; then
            attempt=$((attempt + 1))
            continue
        elif [ "$error" = "slow_down" ]; then
            interval=$((interval + 5))
            attempt=$((attempt + 1))
            continue
        elif [ -n "$error" ]; then
            echo "Authentication error: $error" >&2
            return 1
        fi
        
        attempt=$((attempt + 1))
    done
    
    echo "Authentication timeout" >&2
    return 1
}

# Main execution
if [ "$PAM_TYPE" = "auth" ]; then
    oauth_device_flow "$PAM_USER"
else
    exit 0
fi
EOF

# Make script executable
chmod +x /opt/auth/oauth_auth.sh

# Install jq for JSON parsing
apt install -y jq
```

### Option B: Configure PAM to use the OAuth script

Create PAM configuration for SSH OAuth authentication:

```bash
# Backup original PAM SSH configuration
cp /etc/pam.d/sshd /etc/pam.d/sshd.backup

# Create new PAM configuration for OAuth SSH
cat > /etc/pam.d/sshd << 'EOF'
# PAM configuration for SSH with OAuth Device Flow authentication

# OAuth authentication
auth    required    pam_env.so
auth    required    pam_exec.so expose_authtok /opt/auth/oauth_auth.sh
auth    required    pam_permit.so

# Account management
account required    pam_unix.so
account required    pam_time.so
account required    pam_permit.so

# Session management
session required    pam_unix.so
session required    pam_mkhomedir.so skel=/etc/skel umask=077
session optional    pam_systemd.so

# Password management (not used for OAuth)
password required   pam_deny.so
EOF
```

## Step 5: Configure SSH for OAuth Authentication

Update SSH daemon configuration:

```bash
# Backup original SSH config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Update SSH configuration for OAuth
cat >> /etc/ssh/sshd_config << 'EOF'

# OAuth/PAM Configuration
UsePAM yes
PasswordAuthentication yes
ChallengeResponseAuthentication yes
KbdInteractiveAuthentication yes
AuthenticationMethods keyboard-interactive
PubkeyAuthentication no
PermitRootLogin no

# Allow OAuth users
AllowUsers *
EOF
```

## Step 6: Set Environment Variables

Create environment file for OAuth configuration:

```bash
# Create environment file for PAM OAuth
cat > /etc/environment << 'EOF'
PAM_OAUTH_CLIENT_SECRET=your_actual_client_secret_here
EOF

# Source in profile
echo 'source /etc/environment' >> /etc/profile
```

## Step 7: Create User Management Script

Create a script to manage OAuth users:

```bash
cat > /opt/auth/manage_oauth_users.sh << 'EOF'
#!/bin/bash
# OAuth User Management Script

create_oauth_user() {
    local username="$1"
    local display_name="$2"
    local email="$3"
    
    # Check if user exists
    if id "$username" &>/dev/null; then
        echo "User $username already exists"
        return 0
    fi
    
    # Create user account
    useradd -m -s /bin/bash -c "${display_name}" "$username"
    
    # Set up home directory
    mkdir -p "/home/$username"
    chown "$username:$username" "/home/$username"
    chmod 755 "/home/$username"
    
    # Copy default profile
    cp /etc/skel/.* "/home/$username/" 2>/dev/null || true
    chown -R "$username:$username" "/home/$username"
    
    echo "Created OAuth user: $username"
}

# Usage examples:
# create_oauth_user "john.doe" "John Doe" "john.doe@example.com"
EOF

chmod +x /opt/auth/manage_oauth_users.sh
```

## Step 8: Start and Configure Services

```bash
# Set client secret environment variable
export PAM_OAUTH_CLIENT_SECRET="your_actual_client_secret"

# Start SSSD service
systemctl enable sssd
systemctl start sssd

# Restart SSH service
systemctl restart ssh

# Check service status
systemctl status sssd
systemctl status ssh
```

## Step 9: Testing OAuth Authentication

### Test 1: Direct SSH Login

From the host machine:

```bash
# Attempt SSH login with OAuth user
ssh john.doe@localhost -p 2222

# Follow the device flow instructions displayed
# Visit the URL and enter the code in your browser
# Complete authentication in Keycloak
```

### Test 2: Local Authentication Test

Inside the container:

```bash
# Test PAM authentication directly
su - john.doe

# Should trigger OAuth device flow
```

### Test 3: Debug Authentication

```bash
# Enable SSH debug logging
echo "LogLevel DEBUG" >> /etc/ssh/sshd_config
systemctl restart ssh

# Check authentication logs
tail -f /var/log/auth.log

# Check SSSD logs
tail -f /var/log/sssd/sssd.log
```

## Troubleshooting

### Common Issues

1. **"OAuth module not found" errors:**
   - Install libpam-oauth2 or use the custom script approach
   - Verify script permissions and paths

2. **Network connectivity issues:**
   - Ensure containers can reach Keycloak
   - Check firewall and network configuration
   - Verify Keycloak URLs in configuration

3. **Client secret errors:**
   - Verify client secret in Keycloak admin console
   - Update environment variables and SSSD config
   - Restart services after config changes

4. **User creation failures:**
   - Check if users exist in Keycloak
   - Verify user attribute mappings
   - Use the user management script to pre-create users

### Debug Commands

```bash
# Test OAuth authentication manually
/opt/auth/oauth_auth.sh

# Check PAM configuration
pamtester sshd john.doe authenticate

# Test SSSD configuration
sss_debuglevel 9
systemctl restart sssd

# Check network connectivity to Keycloak
curl -I http://keycloak:8080/realms/hybrid-auth
```

## Security Considerations

1. **Client Secret Management:**
   - Store client secrets securely
   - Use environment variables or secure key stores
   - Rotate secrets regularly

2. **Network Security:**
   - Use HTTPS in production
   - Implement proper firewall rules
   - Consider VPN or private networks

3. **User Session Management:**
   - Configure appropriate session timeouts
   - Implement proper logout procedures
   - Monitor active sessions

4. **Audit and Logging:**
   - Enable comprehensive logging
   - Monitor authentication attempts
   - Set up alerting for failed authentications

## Production Deployment

For production use:

1. **Replace HTTP with HTTPS:**
   ```bash
   # Update all Keycloak URLs to use HTTPS
   sed -i 's/http:/https:/g' /etc/sssd/sssd.conf
   sed -i 's/http:/https:/g' /opt/auth/oauth_auth.sh
   ```

2. **Use proper DNS names:**
   ```bash
   # Replace localhost/keycloak with actual hostnames
   sed -i 's/keycloak:8080/your-keycloak-server.com/g' /opt/auth/oauth_auth.sh
   ```

3. **Implement proper certificate validation:**
   ```bash
   # Add SSL certificate verification to curl commands
   # Update scripts to verify SSL certificates
   ```

4. **Set up monitoring and alerting:**
   ```bash
   # Configure log monitoring
   # Set up health checks
   # Implement failure alerts
   ```

This completes the OAuth/PAM authentication setup for the Ubuntu client. Users can now authenticate via SSH using the OAuth Device Flow with Keycloak as the identity provider.
