# OAuth Device Flow for Linux Services: A Complete Tutorial

## Introduction

This tutorial demonstrates how to implement OAuth 2.0 Device Flow authentication for traditional Linux services like SSH. The OAuth Device Flow (RFC 8628) solves the challenge of authenticating on devices that either lack a web browser or have limited input capabilities.

## Traditional vs OAuth Authentication

### Traditional SSH Authentication Problems

1. **Local Account Management**: Each server maintains its own user accounts
2. **Password Policies**: Difficult to enforce consistent policies across servers
3. **Scalability**: Adding/removing users requires touching every server
4. **Audit Trails**: Limited visibility into authentication events
5. **MFA Complexity**: Difficult to implement multi-factor authentication

### OAuth Device Flow Benefits

1. **Centralized Identity**: Single source of truth for user accounts
2. **Rich Authentication**: Support for MFA, conditional access, SSO
3. **Browser Experience**: Users authenticate in familiar browser environment
4. **Scalability**: Add/remove users centrally
5. **Audit & Compliance**: Comprehensive logging and session management

## Understanding OAuth Device Flow

### The Flow Sequence

```
┌─────────┐   ┌──────────┐   ┌───────────┐   ┌─────────┐
│   SSH   │   │   SSH    │   │ Keycloak  │   │ User's  │
│ Client  │   │ Server   │   │ (OAuth)   │   │Browser  │
└─────────┘   └──────────┘   └───────────┘   └─────────┘
     │             │              │              │
     │─────────────▶│              │              │
     │ ssh user@host│              │              │
     │             │──────────────▶│              │
     │             │ Device Auth   │              │
     │             │ Request       │              │
     │             │◀──────────────│              │
     │             │ Device Code   │              │
     │             │ User Code     │              │
     │◀─────────────│              │              │
     │ Show User    │              │              │
     │ Code & URL   │              │              │
     │             │              │◀─────────────│
     │             │              │ User visits  │
     │             │              │ URL + Code   │
     │             │              │──────────────▶│
     │             │              │ Auth Page    │
     │             │              │◀──────────────│
     │             │              │ Credentials  │
     │             │──────────────▶│              │
     │             │ Poll for     │              │
     │             │ Token        │              │
     │             │◀──────────────│              │
     │             │ Access Token │              │
     │◀─────────────│              │              │
     │ SSH Session │              │              │
     │ Established │              │              │
```

### Key Components

1. **Device Authorization Endpoint**: Where SSH server requests device codes
2. **Device Verification Endpoint**: Where users enter their codes
3. **Token Endpoint**: Where SSH server exchanges device codes for tokens
4. **User Agent**: The user's browser for authentication

## Implementation Details

### 1. PAM Integration

Linux PAM (Pluggable Authentication Modules) allows us to insert OAuth authentication into the standard SSH login process:

```bash
# /etc/pam.d/sshd configuration
auth    required    pam_exec.so    /opt/auth/oauth_auth.sh
auth    include     common-auth
```

**How it works:**
- SSH login triggers PAM authentication
- `pam_exec.so` calls our OAuth script
- Script performs device flow authentication
- Success/failure determines SSH access

### 2. OAuth Authentication Script

The core OAuth logic is implemented in `/opt/auth/oauth_auth.sh`:

```bash
#!/bin/bash
# Key functions:

# 1. Request device authorization
request_device_authorization() {
    curl -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" \
        "$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/auth/device"
}

# 2. Display user code to user
display_user_code() {
    echo "Please visit: $VERIFICATION_URI"
    echo "Enter code: $USER_CODE"
}

# 3. Poll for authorization
poll_for_token() {
    curl -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=$DEVICE_CODE&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" \
        "$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/token"
}
```

### 3. Keycloak Configuration

The OAuth server (Keycloak) requires specific configuration for device flow:

```json
{
  "clientId": "ssh-pam-client",
  "enabled": true,
  "clientAuthenticatorType": "client-secret",
  "secret": "ssh-pam-client-secret-2024-hybrid-auth-lab",
  "attributes": {
    "oauth2.device.authorization.grant.enabled": "true",
    "oauth2.device.code.lifespan": "600",
    "oauth2.device.polling.interval": "5"
  }
}
```

**Key attributes:**
- `oauth2.device.authorization.grant.enabled`: Enables device flow
- `oauth2.device.code.lifespan`: How long device codes are valid (seconds)
- `oauth2.device.polling.interval`: Minimum time between polling requests

## Security Considerations

### Client Authentication

```bash
# Client credentials are stored securely
KEYCLOAK_CLIENT_SECRET="ssh-pam-client-secret-2024-hybrid-auth-lab"
```

**Production considerations:**
- Use environment variables or secure vaults for secrets
- Implement client certificate authentication for enhanced security
- Consider rotating client secrets regularly

### Token Validation

```bash
# Validate tokens before granting access
validate_token() {
    curl -H "Authorization: Bearer $ACCESS_TOKEN" \
        "$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/userinfo"
}
```

### Session Management

The OAuth flow provides rich session information:
- User identity and attributes
- Authentication time and method
- Session lifetime and refresh capabilities

## Testing and Debugging

### Manual Testing

```bash
# 1. Test device authorization endpoint
curl -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=ssh-pam-client&client_secret=ssh-pam-client-secret-2024-hybrid-auth-lab" \
    "http://localhost:8080/realms/hybrid-auth/protocol/openid-connect/auth/device"

# 2. Test token endpoint with device code
curl -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=<DEVICE_CODE>&client_id=ssh-pam-client&client_secret=ssh-pam-client-secret-2024-hybrid-auth-lab" \
    "http://localhost:8080/realms/hybrid-auth/protocol/openid-connect/token"
```

### Automated Testing

```bash
# Comprehensive integration test
./test-oauth-integration.sh

# Interactive device flow demo
./demo-oauth-device-flow.sh
```

### Debugging Common Issues

**1. Invalid Client Error**
```bash
# Check client ID and secret
curl -s "$KEYCLOAK_URL/realms/$REALM/.well-known/openid_configuration" | jq .device_authorization_endpoint
```

**2. Authorization Pending**
```bash
# Normal - user hasn't completed authentication yet
# Continue polling at specified interval
```

**3. Expired Token**
```bash
# Device code has expired - restart flow
# Check device_code_lifespan in client configuration
```

## Production Deployment

### Environment Considerations

1. **HTTPS Required**: Always use HTTPS in production
2. **Network Security**: Secure communication between components
3. **Secret Management**: Use proper secret management systems
4. **Monitoring**: Implement comprehensive logging and monitoring

### Scaling Considerations

1. **Stateless Design**: OAuth flow is naturally stateless
2. **Load Balancing**: Standard techniques apply
3. **Caching**: Consider caching user info and token validation

### Integration with Existing Infrastructure

1. **LDAP/AD Federation**: Keycloak can federate with existing directories
2. **SSO Integration**: Leverage existing SSO solutions
3. **Group Mapping**: Map OAuth groups to Linux groups

## Advanced Use Cases

### Multi-Factor Authentication

```json
{
  "authenticationFlows": [{
    "alias": "Device Flow with MFA",
    "requirements": [
      "PASSWORD",
      "OTP"
    ]
  }]
}
```

### Conditional Access

```javascript
// Keycloak script-based policies
if (user.getAttribute('department') === 'finance' && 
    context.getClientId() === 'ssh-pam-client') {
    grant = true;
}
```

### Session Management

```bash
# Refresh tokens for long-lived sessions
refresh_token() {
    curl -X POST \
        -d "grant_type=refresh_token&refresh_token=$REFRESH_TOKEN&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" \
        "$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/token"
}
```

## Conclusion

OAuth Device Flow provides a modern, secure, and scalable approach to authentication for traditional Linux services. This tutorial demonstrates:

- **Technical Implementation**: How to integrate OAuth with PAM
- **Security Best Practices**: Proper client authentication and token validation
- **Operational Considerations**: Testing, debugging, and production deployment
- **Advanced Features**: MFA, conditional access, and session management

The approach bridges the gap between modern identity management and traditional infrastructure, providing a path to modernize authentication without requiring complete infrastructure replacement.

## Further Reading

- [RFC 8628: OAuth 2.0 Device Authorization Grant](https://tools.ietf.org/html/rfc8628)
- [Keycloak Device Flow Documentation](https://www.keycloak.org/docs/latest/securing_apps/#device-flow)
- [Linux PAM Documentation](http://www.linux-pam.org/Linux-PAM-html/)
- [OAuth 2.0 Security Best Practices](https://tools.ietf.org/html/draft-ietf-oauth-security-topics)
