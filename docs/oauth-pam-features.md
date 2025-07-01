# OAuth/PAM Authentication Features

This document summarizes the OAuth/PAM authentication features implemented in the hybrid authentication lab.

## Overview

The hybrid authentication lab now supports OAuth Device Flow authentication for SSH logins on the Ubuntu client. This creates a complete authentication chain:

**Windows AD → Keycloak (LDAP) → OAuth Tokens → Linux SSH**

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Windows AD    │    │    Keycloak     │    │ Ubuntu Client   │
│   (QEMU VM)     │◄───┤   (Container)   │◄───┤  (Container)    │
│                 │    │                 │    │                 │
│ • Domain Users  │    │ • LDAP Provider │    │ • OAuth/PAM     │
│ • Groups        │    │ • OAuth Server  │    │ • SSH Server    │
│ • Policies      │    │ • Device Flow   │    │ • User Sessions │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Authentication Flow

1. **User attempts SSH login**: `ssh user@localhost -p 2222`
2. **PAM triggers OAuth**: Custom PAM module initiates device flow
3. **Device code generation**: Keycloak generates device and user codes
4. **User authorization**: User visits URL and enters code in browser
5. **AD authentication**: User authenticates against Windows AD via LDAP
6. **Token issuance**: Keycloak issues OAuth access/refresh tokens
7. **Token validation**: PAM validates tokens with Keycloak
8. **Session creation**: Local user account and SSH session created

## Components

### 1. OAuth Authentication Script (`/opt/auth/oauth_auth.sh`)
- Implements OAuth 2.0 Device Authorization Grant (RFC 8628)
- Handles device code request and polling
- Validates user tokens with Keycloak
- Creates local user accounts automatically
- Comprehensive error handling and logging

### 2. PAM Configuration (`/etc/pam.d/sshd`)
- Integrates OAuth script with SSH authentication
- Creates home directories automatically
- Manages user sessions and environment
- Fallback to traditional authentication if needed

### 3. SSH Configuration
- Configured for keyboard-interactive authentication
- Supports OAuth device flow interaction
- Automatic user account creation
- Session management and logging

### 4. User Management Scripts
- `oauth-create`: Create OAuth users
- `oauth-users`: List OAuth users  
- `oauth-remove`: Remove OAuth users
- Automated user provisioning from OAuth attributes

### 5. Setup and Configuration Scripts
- `setup-oauth-pam.sh`: Complete OAuth/PAM setup
- `quick-start-oauth.sh`: Automated quick setup
- `test-oauth-device-flow.sh`: OAuth flow testing
- Environment and service management

## Security Features

### Token Security
- Secure client secret management
- Token validation and introspection
- Automatic token expiration handling
- Refresh token support

### Network Security
- TLS/HTTPS support for production
- Configurable Keycloak URLs
- Network isolation between containers
- Firewall-friendly device flow

### User Management
- Automatic user provisioning
- Home directory creation
- Permission management
- Session auditing and logging

### Authentication Security
- Multi-factor authentication ready
- Device flow prevents credential exposure
- Time-limited authentication codes
- Centralized authentication logging

## Configuration Options

### Environment Variables
```bash
KEYCLOAK_URL=http://keycloak:8080              # Keycloak server URL
KEYCLOAK_REALM=hybrid-auth                     # Keycloak realm name
KEYCLOAK_CLIENT_ID=ssh-pam-client             # OAuth client ID
KEYCLOAK_CLIENT_SECRET=secret123               # OAuth client secret
OAUTH_TIMEOUT=300                              # Authentication timeout
OAUTH_POLL_INTERVAL=5                          # Token polling interval
```

### Keycloak Client Configuration
- **Client ID**: `ssh-pam-client`
- **Client Protocol**: `openid-connect`
- **Access Type**: `confidential`
- **Standard Flow**: Enabled
- **Device Authorization Grant**: Enabled
- **Valid Redirect URIs**: `http://localhost:*`, `urn:ietf:wg:oauth:2.0:oob`

### SSH Configuration
- **Authentication Methods**: `keyboard-interactive`
- **PAM Authentication**: Enabled
- **Password Authentication**: Enabled (for OAuth flow)
- **Public Key Authentication**: Disabled (can be re-enabled)
- **Automatic Home Directory Creation**: Enabled

## Usage Examples

### Basic SSH Login
```bash
# SSH login with OAuth authentication
ssh john.doe@localhost -p 2222

# Follow the displayed instructions:
# 1. Visit the verification URL
# 2. Enter the device code
# 3. Complete authentication in browser
# 4. SSH session will be established
```

### User Management
```bash
# Create OAuth user
docker exec ubuntu-client oauth-create alice.cooper "Alice Cooper" "alice@example.com"

# List OAuth users
docker exec ubuntu-client oauth-users

# Remove OAuth user
docker exec ubuntu-client oauth-remove alice.cooper
```

### Testing and Debugging
```bash
# Test OAuth device flow directly
KEYCLOAK_CLIENT_SECRET=secret123 ./examples/test-oauth-device-flow.sh testuser

# Debug PAM authentication
docker exec ubuntu-client tail -f /var/log/auth.log

# Check OAuth environment
docker exec ubuntu-client cat /etc/default/oauth-auth

# Validate OAuth script
docker exec ubuntu-client /opt/auth/oauth_auth.sh
```

## Troubleshooting

### Common Issues

1. **"Cannot connect to Keycloak"**
   - Check container networking: `docker network ls`
   - Verify Keycloak is running: `docker ps | grep keycloak`
   - Test connectivity: `docker exec ubuntu-client curl -I http://keycloak:8080`

2. **"Client secret not set"**
   - Set environment variable: `export KEYCLOAK_CLIENT_SECRET=your_secret`
   - Update config file: `echo 'KEYCLOAK_CLIENT_SECRET=secret' >> /etc/default/oauth-auth`
   - Restart SSH service: `systemctl restart ssh`

3. **"Authorization pending" timeout**
   - Check Keycloak client configuration
   - Verify device flow is enabled
   - Ensure user exists in Keycloak/AD
   - Check browser network connectivity

4. **"User creation failed"**
   - Check container permissions
   - Verify user doesn't already exist
   - Check home directory space
   - Review system logs

### Debug Commands
```bash
# Enable debug logging
docker exec ubuntu-client bash -c "echo 'debug_level = 9' >> /etc/default/oauth-auth"

# Test OAuth script manually
docker exec ubuntu-client bash -c "
export PAM_TYPE=auth
export PAM_USER=testuser
source /etc/default/oauth-auth
/opt/auth/oauth_auth.sh
"

# Check PAM configuration
docker exec ubuntu-client pamtester sshd testuser authenticate

# Monitor authentication logs
docker exec ubuntu-client tail -f /var/log/auth.log

# Test network connectivity
docker exec ubuntu-client curl -v http://keycloak:8080/realms/hybrid-auth
```

## Production Considerations

### Security Hardening
- Use HTTPS for all Keycloak communications
- Implement proper certificate validation
- Use secure client secret storage (e.g., HashiCorp Vault)
- Enable comprehensive audit logging
- Implement rate limiting and DDoS protection

### High Availability
- Deploy Keycloak in cluster mode
- Use external database for Keycloak
- Implement load balancing
- Set up monitoring and alerting
- Plan for backup and disaster recovery

### Performance Optimization
- Tune OAuth token lifetimes
- Implement token caching
- Optimize network configurations
- Monitor resource usage
- Scale containers as needed

### Compliance and Governance
- Implement user access reviews
- Set up compliance reporting
- Configure session recording
- Implement data retention policies
- Plan for regulatory requirements

## Integration Points

### Windows AD Integration
- LDAP provider configuration in Keycloak
- User and group synchronization
- Password policy enforcement
- Group-based access control

### Keycloak Integration
- OAuth 2.0 Device Authorization Grant
- OpenID Connect user information
- Token introspection and validation
- Client credential management

### Linux System Integration
- PAM module integration
- SSH daemon configuration
- User account management
- Home directory provisioning
- System logging and auditing

## Future Enhancements

### Planned Features
- Multi-factor authentication support
- Role-based access control (RBAC)
- Just-in-time (JIT) user provisioning
- Advanced session management
- Integration with enterprise PKI

### Possible Extensions
- Support for other authentication methods
- Integration with LDAP/AD groups
- Custom user attribute mapping
- Advanced audit and compliance features
- Support for federated authentication

This OAuth/PAM implementation provides a robust, secure, and scalable authentication solution that bridges Windows AD and Linux systems through modern OAuth standards.
