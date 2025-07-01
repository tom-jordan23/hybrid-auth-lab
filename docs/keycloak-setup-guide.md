# Keycloak Realm Configuration Guide

This guide walks you through setting up a Keycloak realm and configuring OAuth providers with device flow support.

## Prerequisites

1. Ensure Keycloak is running:
   ```bash
   ./build.sh
   ./network-info.sh  # Check status
   ```

2. Access Keycloak Admin Console: http://localhost:8080 (or your local IP)
   - Username: `admin`
   - Password: `admin_password`

## Step 1: Configure LDAP User Federation (Windows AD Integration)

Before creating OAuth clients, you'll want to integrate your Windows AD users into Keycloak via LDAP. This allows existing AD users to authenticate through Keycloak.

### Prerequisites for AD Integration

1. **Ensure Windows AD Server is running**:
   ```bash
   cd windows-ad-server
   ./start-vm.sh  # Start the Windows AD server VM
   ```

2. **Get AD Server Network Information**:
   - Windows AD Server IP (typically in QEMU bridge network)
   - Domain Controller hostname (e.g., `dc1.example.com`)
   - LDAP port: 389 (or 636 for LDAPS)

3. **Test Network Connectivity**:
   ```bash
   # Test from Ubuntu SSH container
   ssh vagrant@localhost -p 2222
   # Inside container:
   nslookup dc1.example.com
   telnet DC_IP_ADDRESS 389
   ```

### Configure LDAP User Federation

1. **Navigate to User Federation**
   - Go to **User federation** in the left sidebar
   - Click "Add LDAP providers"
   - Select **"ldap"**

2. **Basic LDAP Configuration**
   - **Console display name**: `Windows Active Directory`
   - **Priority**: `0` (highest priority)
   - **Import users**: ✅ On
   - **Edit mode**: `READ_ONLY` (or `WRITABLE` if you want to allow password changes)
   - **Sync registrations**: ✅ On
   - **Vendor**: `Active Directory`
   - **Username LDAP attribute**: `sAMAccountName`
   - **RDN LDAP attribute**: `cn`
   - **UUID LDAP attribute**: `objectGUID`
   - **User object classes**: `person, organizationalPerson, user`

3. **LDAP Connection Settings**
   - **Connection URL**: `ldap://DC_IP_ADDRESS:389` (or ldaps://DC_IP_ADDRESS:636 for SSL)
   - **Enable StartTLS**: ❌ Off (unless you have SSL configured)
   - **Use Truststore SPI**: `Only for ldaps`
   - **Connection pooling**: ✅ On
   - **Connection timeout**: `5000`
   - **Read timeout**: `10000`

4. **LDAP Authentication Settings**
   - **Bind type**: `simple`
   - **Bind DN**: `CN=Administrator,CN=Users,DC=example,DC=com` (adjust for your domain)
   - **Bind credential**: `YourAdminPassword` (Administrator password)

5. **LDAP Search Settings**
   - **Users DN**: `CN=Users,DC=example,DC=com` (adjust for your domain)
   - **Search scope**: `Subtree`
   - **User LDAP filter**: Leave empty or use `(objectClass=user)(!(objectClass=computer))`

6. **Test Connection**
   - Click **"Test connection"** - should show success
   - Click **"Test authentication"** - should show success

7. **Save Configuration**
   - Click **"Save"**

### Synchronize Users from AD

1. **Initial User Import**
   - After saving, scroll down to **"Synchronization settings"**
   - **Periodic full sync**: ✅ Enable (set to run daily)
   - **Full sync period**: `86400` (24 hours)
   - **Periodic changed users sync**: ✅ Enable
   - **Changed users sync period**: `3600` (1 hour)
   - Click **"Save"**

2. **Manual Sync (First Time)**
   - Click **"Synchronize all users"** (this imports all AD users immediately)
   - Wait for completion - check the server logs if needed

3. **Verify User Import**
   - Go to **Users** in the left sidebar
   - You should see users from your AD domain
   - Click on a user to verify attributes are populated

### Configure LDAP Mappers

LDAP mappers define how AD attributes map to Keycloak user attributes:

1. **Navigate to Mappers**
   - Go to your LDAP provider → **Mappers** tab
   - Default mappers should be automatically created

2. **Common LDAP Mappers** (verify these exist):
   - **username**: Maps `sAMAccountName` to username
   - **email**: Maps `mail` to email
   - **first name**: Maps `givenName` to firstName
   - **last name**: Maps `sn` to lastName
   - **full name**: Maps `cn` to full name

3. **Add Group Mapper (Optional)**
   - Click **"Create"**
   - **Name**: `group-ldap-mapper`
   - **Mapper type**: `group-ldap-mapper`
   - **LDAP groups DN**: `CN=Users,DC=example,DC=com`
   - **Group name LDAP attribute**: `cn`
   - **Group object classes**: `group`
   - **Membership LDAP attribute**: `member`
   - **Mode**: `READ_ONLY`
   - Click **"Save"**

### Test AD User Authentication

1. **Verify User Login**
   - Go to your realm's account console: `http://localhost:8080/realms/hybrid-auth/account`
   - Try logging in with an AD user:
     - **Username**: `aduser` (sAMAccountName from AD)
     - **Password**: `their_ad_password`

2. **Test with OAuth Device Flow**
   ```bash
   cd examples
   ./test-device-flow.sh
   # When prompted, use AD credentials
   ```

### Troubleshooting LDAP Integration

**Connection Issues:**
```bash
# Test LDAP connectivity from Ubuntu container
ssh vagrant@localhost -p 2222
sudo apt-get update && sudo apt-get install -y ldap-utils
ldapsearch -x -H ldap://DC_IP:389 -D "CN=Administrator,CN=Users,DC=example,DC=com" -W -b "DC=example,DC=com"
```

**Common Issues:**
1. **"Could not connect"**: Check network connectivity and firewall rules
2. **"Authentication failed"**: Verify bind DN and password
3. **"No users imported"**: Check Users DN and LDAP filter
4. **"Invalid DN syntax"**: Ensure proper DN format for your domain

**Debug LDAP Queries:**
- Enable DEBUG logging in Keycloak for `org.keycloak.storage.ldap`
- Check Keycloak server logs during sync operations

## Step 2: Create a New Realm

1. **Login to Keycloak Admin Console**
   - Navigate to http://localhost:8080
   - Login with admin credentials

2. **Create Realm**
   - Click the dropdown next to "Keycloak" (top-left)
   - Click "Create Realm"
   - **Realm name**: `hybrid-auth` (or your preferred name)
   - **Enabled**: ✅ (checked)
   - Click "Create"

3. **Configure Realm Settings**
   - Go to **Realm Settings** → **General**
   - **Display name**: `Hybrid Authentication Lab`
   - **HTML Display name**: `<b>Hybrid Auth Lab</b>`
   - **Frontend URL**: `http://localhost:8080` (or your local IP)
   - Click "Save"

## Step 3: Configure OAuth Device Flow

### Enable Device Flow

1. **Go to Realm Settings → Advanced**
   - **OAuth 2.0 Device Authorization Grant**: ✅ Enable
   - Click "Save"

### Configure Device Flow Settings

2. **Go to Realm Settings → Tokens**
   - **Device Code Lifespan**: `600` (10 minutes)
   - **Device Polling Interval**: `5` (seconds)
   - Click "Save"

## Step 4: Create OAuth Client for Device Flow

1. **Navigate to Clients**
   - Go to **Clients** in the left sidebar
   - Click "Create client"

2. **Client Configuration - General Settings**
   - **Client type**: `OpenID Connect`
   - **Client ID**: `device-flow-client`
   - **Name**: `Device Flow Application`
   - **Description**: `OAuth client for device flow authentication`
   - Click "Next"

3. **Client Configuration - Capability Config**
   - **Client authentication**: ✅ On (for confidential client)
   - **Authorization**: ❌ Off
   - **Authentication flow**: 
     - ✅ Standard flow
     - ✅ Device authorization grant
     - ❌ Direct access grants (disable for security)
     - ❌ Implicit flow (disable for security)
   - Click "Next"

4. **Client Configuration - Login Settings**
   - **Root URL**: `http://localhost:3000` (adjust for your app)
   - **Home URL**: `http://localhost:3000`
   - **Valid redirect URIs**: 
     - `http://localhost:3000/*`
     - `http://127.0.0.1:3000/*`
   - **Valid post logout redirect URIs**: `http://localhost:3000/logout`
   - **Web origins**: `http://localhost:3000`
   - Click "Save"

## Step 5: Configure Client Advanced Settings

1. **Go to your client → Settings → Advanced**
   - **Access Token Lifespan**: `300` (5 minutes)
   - **Client Session Idle**: `1800` (30 minutes)
   - **Client Session Max**: `36000` (10 hours)
   - **Proof Key for Code Exchange Code Challenge Method**: `S256`
   - Click "Save"

2. **Get Client Credentials**
   - Go to **Credentials** tab
   - Copy the **Client secret** (you'll need this for your application)

## Step 6: Create Users for Testing

1. **Navigate to Users**
   - Go to **Users** in the left sidebar
   - Click "Create new user"

2. **Create Test User**
   - **Username**: `testuser`
   - **Email**: `testuser@example.com`
   - **First name**: `Test`
   - **Last name**: `User`
   - **Email verified**: ✅ On
   - **Enabled**: ✅ On
   - Click "Create"

3. **Set User Password**
   - Go to **Credentials** tab
   - Click "Set password"
   - **Password**: `TestPassword123!`
   - **Temporary**: ❌ Off
   - Click "Save"

## Step 7: Configure Identity Provider (Optional)

If you want to add external OAuth providers (Google, GitHub, etc.):

1. **Navigate to Identity Providers**
   - Go to **Identity providers** in the left sidebar
   - Select your provider (e.g., "Google", "GitHub", "Microsoft")

2. **Google OAuth Setup Example**
   - **Alias**: `google`
   - **Display name**: `Sign in with Google`
   - **Client ID**: `your-google-client-id`
   - **Client Secret**: `your-google-client-secret`
   - **Default Scopes**: `openid profile email`
   - Click "Save"

## Step 8: Test Device Flow

### Method 1: Using curl

1. **Start Device Authorization**
   ```bash
   curl -X POST http://localhost:8080/realms/hybrid-auth/protocol/openid-connect/auth/device \\
     -H "Content-Type: application/x-www-form-urlencoded" \\
     -d "client_id=device-flow-client"
   ```

2. **Response will include:**
   ```json
   {
     "device_code": "...",
     "user_code": "ABCD-EFGH",
     "verification_uri": "http://localhost:8080/realms/hybrid-auth/device",
     "verification_uri_complete": "http://localhost:8080/realms/hybrid-auth/device?user_code=ABCD-EFGH",
     "expires_in": 600,
     "interval": 5
   }
   ```

3. **User visits verification URI and enters code**

4. **Poll for token**
   ```bash
   curl -X POST http://localhost:8080/realms/hybrid-auth/protocol/openid-connect/token \\
     -H "Content-Type: application/x-www-form-urlencoded" \\
     -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \\
     -d "device_code=YOUR_DEVICE_CODE" \\
     -d "client_id=device-flow-client" \\
     -d "client_secret=YOUR_CLIENT_SECRET"
   ```

### Method 2: Using Test Application

See the `test-device-flow.js` script in this directory for a complete Node.js example.

## Step 9: Export Realm Configuration

1. **Export for Version Control**
   ```bash
   ./config-manager.sh export keycloak
   ```

2. **Manual Export (Alternative)**
   - Go to **Realm Settings** → **Action** → **Export**
   - **Export groups and roles**: ✅ On
   - **Export clients**: ✅ On
   - **Export users**: ✅ On (for development only)
   - Click "Export"
   - Save the JSON file to `keycloak-server/config/import/`

## Common Configuration Values

### URLs for Local Development
- **Realm URL**: `http://localhost:8080/realms/hybrid-auth`
- **Device Authorization Endpoint**: `http://localhost:8080/realms/hybrid-auth/protocol/openid-connect/auth/device`
- **Token Endpoint**: `http://localhost:8080/realms/hybrid-auth/protocol/openid-connect/token`
- **Userinfo Endpoint**: `http://localhost:8080/realms/hybrid-auth/protocol/openid-connect/userinfo`

### URLs for Network Access
Replace `localhost` with your local IP (use `./network-info.sh` to find it):
- **Realm URL**: `http://YOUR_LOCAL_IP:8080/realms/hybrid-auth`

## Troubleshooting

### Device Flow Not Working
1. Check that device flow is enabled in Realm Settings → Advanced
2. Verify client has "Device authorization grant" enabled
3. Check token lifespan settings
4. Ensure device code hasn't expired

### Authentication Issues
1. Verify user credentials
2. Check user is enabled and email verified
3. Review client redirect URIs
4. Check browser console for CORS errors

### Network Access Issues
1. Run `./network-info.sh` to verify connectivity
2. Check firewall settings
3. Verify Keycloak is accessible from your network

## Next Steps

1. **Integrate with your application** using the device flow
2. **Configure SSH integration** with Keycloak (OIDC/SAML)
3. **Set up Windows AD integration** for hybrid authentication
4. **Configure role-based access control (RBAC)**

## Security Considerations

- Use HTTPS in production
- Set appropriate token lifespans
- Enable PKCE for public clients
- Regularly rotate client secrets
- Implement proper logout flows
- Configure session timeouts appropriately
