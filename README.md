# OAuth Device Flow Tutorial: Modernizing Linux Authentication

> **New to OAuth Device Flow?** Start with the **[Getting Started Guide](GETTING-STARTED.md)** for a quick introduction.

This project demonstrates how to implement **OAuth 2.0 Device Flow** authentication for traditional Linux services like SSH. Instead of relying solely on local user accounts or complex Kerberos setups, this tutorial shows how to integrate modern federated authentication with existing Linux infrastructure.

## What You'll Learn

- How OAuth 2.0 Device Flow works for device authentication
- Integrating OAuth with Linux PAM (Pluggable Authentication Modules)
- Bridging traditional services (SSH) with modern identity providers
- Setting up Keycloak as an OAuth 2.0 Authorization Server
- Creating a hybrid authentication environment that can federate with Active Directory

## The Problem This Solves

Traditional Linux authentication often relies on:
- Local `/etc/passwd` accounts (not centralized)
- LDAP/AD with Kerberos (complex, requires domain joining)
- SSH keys (difficult to manage at scale)

This tutorial demonstrates a modern approach using **OAuth Device Flow** that provides:
- ✅ Centralized identity management
- ✅ No complex domain joining required
- ✅ Works with existing SSH infrastructure
- ✅ Supports multi-factor authentication
- ✅ Integration with modern identity providers
- ✅ Audit trails and session management

## Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Keycloak      │    │  Ubuntu SSHD    │    │  Windows AD     │
│ (OAuth Server)  │    │ (SSH + OAuth)   │    │ (User Source)   │
│   Port: 8080    │    │  Port: 2222     │    │  Port: 389/636  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │  Docker Bridge  │
                    │  172.20.0.0/16  │
                    └─────────────────┘
```

**Components:**
- **Keycloak Server** (Docker) - OAuth 2.0 Authorization Server with OIDC support
- **Ubuntu SSHD Client** (Docker) - Linux server with OAuth-enabled PAM authentication
- **Windows AD Server** (QEMU) - Traditional Active Directory for user federation

## Understanding OAuth Device Flow

The **OAuth 2.0 Device Flow** (RFC 8628) is designed for devices that either lack a browser or have limited input capabilities. It's perfect for SSH authentication because:

1. **Device Request**: SSH server requests a device code from the OAuth server
2. **User Code**: User receives a short code to enter in a browser
3. **Browser Authentication**: User completes authentication in a full browser experience
4. **Token Polling**: SSH server polls for the authentication result
5. **Access Granted**: Upon successful authentication, SSH access is granted

### Traditional SSH Login Flow
```
User → SSH Client → SSH Server → /etc/passwd → ✅/❌
```

### OAuth Device Flow SSH Login
```
User → SSH Client → SSH Server → OAuth Server → Browser Auth → ✅/❌
                     ↓
              (PAM OAuth Module)
```

This approach provides:
- **Better Security**: MFA, conditional access, session management
- **Better UX**: Rich browser-based authentication experience
- **Better Management**: Centralized user and policy management

## Complete Quick Start (Fresh Install)

### Prerequisites
- Linux/macOS with Docker and Docker Compose
- **QEMU/KVM for Windows VM** (required for Active Directory)
- **Packer** (required for building Windows VM)
- At least 8GB RAM and 30GB free disk space
- CPU with virtualization support (Intel VT-x or AMD-V)

### Step 1: Install Prerequisites
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install docker.io docker-compose qemu-kvm qemu-system-x86 packer jq

# Fedora/RHEL  
sudo dnf install docker docker-compose qemu-kvm qemu-system-x86 packer jq

# Add user to required groups
sudo usermod -a -G docker $USER
sudo usermod -a -G kvm $USER

# Logout and login again for group changes
```

### Step 2: Clone with Submodules and Build Windows AD First
```bash
# Clone the repository with Windows AD server submodule
git clone --recursive <this-repo>
cd hybrid-auth-lab

# If you already cloned without --recursive, initialize submodules:
# git submodule update --init --recursive

# Make scripts executable
chmod +x *.sh
chmod +x windows-ad-server/*.sh

# Build Windows AD server FIRST (required for authentication)
cd windows-ad-server
./build-vm.sh              # Takes 15-20 minutes
./start-vm.sh               # Start the AD domain controller
./status.sh                 # Verify AD is running
cd ..

# Now build OAuth components with AD integration
./build.sh
```

**Why Windows AD First?**
- Keycloak needs Active Directory running to configure LDAP federation
- AD provides the user directory and group memberships for OAuth claims
- SSH authentication will use AD credentials via OAuth Device Flow

**What this builds:**
- **Keycloak OAuth server** (port 8080) with hybrid-auth realm
- **Ubuntu SSH server** (port 2222) with OAuth PAM integration  
- **Windows Server 2022** with Active Directory (domain: hybrid.local)
- **LDAP Federation** between Keycloak and Active Directory
- **OAuth Device Flow** with AD group membership claims

**Build time:** 20-30 minutes (downloads Windows Server ISO)

### Step 3: Verify Everything is Running
```bash
# Quick status overview
./status.sh

# Comprehensive status check (if needed)
./check-status.sh

# Expected quick status:
# ✅ Docker Components: Running
# ✅ Keycloak OAuth Server: Accessible  
# ✅ SSH Server (OAuth): Listening
# ✅ Windows AD Server: Running + LDAP Ready
# 🎉 Overall Status: READY FOR TESTING
```

### Step 4: Test Active Directory Authentication
```bash
# Test OAuth Device Flow with AD authentication
./demo-oauth-device-flow.sh

# Test SSH with Active Directory user
ssh Administrator@localhost -p 2222
```

# Test OAuth Device Flow with AD authentication
./demo-oauth-device-flow.sh

# Test SSH with Active Directory user
ssh aduser@localhost -p 2222
```

**Expected authentication flow:**
1. SSH triggers OAuth Device Flow
2. User completes authentication in browser
3. Keycloak authenticates against Active Directory via LDAP
4. AD group memberships are included in OAuth token claims
5. SSH session established with AD user identity

### Step 4: Access Admin Interfaces

**Keycloak Admin Console:**
- URL: http://localhost:8080/admin
- Login: admin/admin_password
- Check: User Federation → Windows AD LDAP (should show users synced from AD)

**Windows AD Server:**
- RDP: `rdesktop localhost:3389`
- Domain: hybrid.local
- Login: Administrator/[password in VM scripts]
- Manage: Active Directory Users and Computers

**Pre-configured OAuth Details:**
- **Client ID**: `ssh-pam-client`
- **Client Secret**: `ssh-pam-client-secret-2024-hybrid-auth-lab`
- **Test Users**: admin/admin, testuser/testpass

## Deep Dive: How It Works

### PAM Integration Architecture

The OAuth integration works through Linux PAM (Pluggable Authentication Modules):

```
SSH Login Request
       ↓
   PAM Auth Stack
       ↓
  OAuth PAM Module (/opt/auth/oauth_auth.sh)
       ↓
  Device Flow Request → Keycloak
       ↓
  User Code Generation
       ↓
  Browser Authentication (User)
       ↓
  Token Validation
       ↓
  SSH Access Granted/Denied
```

**Key Files:**
- `/etc/pam.d/sshd` - PAM configuration for SSH
- `/opt/auth/oauth_auth.sh` - OAuth Device Flow script
- `/etc/default/oauth-auth` - OAuth client configuration

### OAuth Client Configuration

The tutorial includes a pre-configured Keycloak OAuth client:

```json
{
  "clientId": "ssh-pam-client",
  "secret": "ssh-pam-client-secret-2024-hybrid-auth-lab",
  "attributes": {
    "oauth2.device.authorization.grant.enabled": "true"
  }
}
```

**Why Device Flow?**
- SSH servers often don't have browsers
- Users can authenticate on their primary device
- Supports rich authentication flows (MFA, SSO, etc.)
- No need to embed credentials in scripts

### Environment Configuration

```bash
# OAuth client settings (in SSH container)
KEYCLOAK_URL=http://keycloak:8080
KEYCLOAK_REALM=hybrid-auth
KEYCLOAK_CLIENT_ID=ssh-pam-client
KEYCLOAK_CLIENT_SECRET=ssh-pam-client-secret-2024-hybrid-auth-lab
```

## Advanced Setup

## Advanced Setup

### Option 1: Docker-Only Setup (Minimal)

For OAuth Device Flow testing without Windows AD:

```bash
# Start only Docker components
docker compose up -d

# Check status
docker compose ps

# View logs to understand startup process
docker compose logs keycloak-server
docker compose logs ubuntu-sshd-client
```

**What happens during startup:**
- Keycloak imports the pre-configured realm (`hybrid-auth`)
- OAuth client (`ssh-pam-client`) is automatically configured
- Ubuntu container sets up SSH with OAuth PAM integration
- Test users are created in Keycloak

### Option 2: Full Hybrid Setup (Docker + Windows VM)

For complete Active Directory integration:

```bash
# 1. Start Docker components first
./build.sh

# 2. Build Windows AD server
cd windows-ad-server
./build-vm.sh  # Takes 15-20 minutes

# 3. Start Windows AD server
./start-vm.sh

# 4. Verify Windows AD is running
./status.sh

# 5. Configure Keycloak to use Windows AD
cd ..
./setup-ad-ldap.sh
```

### Windows AD Server Details

**Build Process:**
- Downloads Windows Server 2022 evaluation ISO
- Creates VM with Packer automation
- Installs and configures Active Directory
- Creates test users and organizational units
- Enables LDAP/LDAPS services

**VM Specifications:**
- OS: Windows Server 2022 Standard
- RAM: 4GB (configurable)
- Disk: 40GB (dynamic)
- Network: Bridge to Docker network

**Default Credentials:**
- Administrator: See `windows-ad-server/scripts/` for password
- Domain: HYBRID.LOCAL
- LDAP: Enabled on ports 389/636

### 2. Start Windows AD Server (QEMU)

```bash
cd windows-ad-server
./start-vm.sh
```

### 3. Access Services

**Local Access:**
- **Keycloak Admin Console**: http://localhost:8080
  - Username: `admin`
  - Password: `admin_password`

- **Ubuntu SSHD Client**: 
  ```bash
  ssh vagrant@localhost -p 2222
  # Password: SecureUser123!
  ```

**Local Network Access:**
- Run `./network-info.sh` to get your local IP and access information
- Services are accessible from other devices on your local network
- **Keycloak**: `http://YOUR_LOCAL_IP:8080`
- **SSH**: `ssh vagrant@YOUR_LOCAL_IP -p 2222`

**Windows AD Server**: Connect via RDP or manage through QEMU console

## Building from Scratch

### Docker Services

The Docker Compose setup will automatically:
- Pull and configure Keycloak with PostgreSQL
- Build the Ubuntu SSHD client image
- Create a bridge network for inter-service communication

### Windows Server

Build the Windows AD server VM:
```bash
cd windows-ad-server
packer build windows-2022-ad-ldif.json
```

## Configuration

### Keycloak Configuration
- Custom configurations: `keycloak-server/config/`
- Custom themes: `keycloak-server/themes/`

### Ubuntu Client Configuration  
- SSH configurations: `linux-client/config/`
- SSSD/AD integration configs will be mounted here

### Windows AD Server
- Configured via Packer templates and answer files
- LDIF test users included

## Tutorial: Configuration Management

Understanding how to manage OAuth and PAM configurations is crucial for implementing this in production environments.

### Configuration Architecture

The tutorial demonstrates a development workflow where configurations can be:
1. **Developed** in running containers (live testing)
2. **Exported** to git repository (version control)
3. **Imported** to other environments (deployment)

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Git Repo      │    │  Running        │    │  New Environment│
│  (Configs)      │ ←→ │  Containers     │ → │  (Deploy)       │
│                 │    │  (Development)  │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### OAuth Configuration Files

**Keycloak Realm Configuration:**
- File: `keycloak-server/config/realm-hybrid-auth.json`
- Contains: OAuth clients, users, authentication flows, mappers
- Management: Export from Keycloak admin console or via API

**SSH/PAM OAuth Configuration:**
- Files: `linux-client/config/`
- Contains: PAM rules, OAuth client settings, SSSD configuration
- Management: Direct file editing or container runtime changes

### Configuration Workflow Tutorial

**Step 1: Start with base configuration**
```bash
./build.sh  # Starts with pre-configured OAuth setup
```

**Step 2: Make changes via Keycloak Admin Console**
```bash
# Access Keycloak admin console
open http://localhost:8080/admin
# Login: admin/admin
# Navigate to 'hybrid-auth' realm
# Modify OAuth client settings, add users, etc.
```

**Step 3: Export changes to git**
```bash
# Export all configurations
./config-manager.sh export

# Or export specific services
./config-manager.sh export keycloak
./config-manager.sh export sshd
```

**Step 4: Version control your changes**
```bash
git add .
git commit -m "Updated OAuth client configuration"
```

**Step 5: Deploy to other environments**
```bash
# In a new environment
./build.sh
./config-manager.sh import  # Applies your custom configurations
```

### Interactive Configuration Management

```bash
# Open configuration files for editing
./config-manager.sh edit keycloak  # Opens keycloak-server/config/
./config-manager.sh edit sshd      # Opens linux-client/config/

# Monitor for changes and auto-export
./config-manager.sh watch

# Create backups before major changes
./config-manager.sh backup

# Restore from backup if needed
./config-manager.sh restore backups/20240701_101530
```

### Quick Commands

```bash
# Export all configurations from running containers
./config-manager.sh export

# Export only Keycloak configuration  
./config-manager.sh export keycloak

# Export only SSH/PAM configuration
./config-manager.sh export sshd

# Import configurations to running containers
./config-manager.sh import

# Edit configuration files
./config-manager.sh edit keycloak
./config-manager.sh edit sshd

# Create backup
./config-manager.sh backup

# Watch for changes and auto-export
./config-manager.sh watch

# Show configuration status
./config-manager.sh status
```

### Configuration Directories

- **Keycloak**: `keycloak-server/config/`
  - `import/` - Realm configurations for import
  - `exported/` - Auto-exported configurations
  - Custom Keycloak configuration files

- **Ubuntu SSHD**: `linux-client/config/`
  - `exported/` - Auto-exported configurations
  - `*.sample` - Template configuration files
  - SSH, PAM, SSSD, and Kerberos configurations

### Development Workflow Example

```bash
# 1. Start services
./build.sh

# 2. Configure Keycloak realm via web UI (http://localhost:8080)
# 3. Configure SSH/PAM by connecting to container
ssh vagrant@localhost -p 2222

# 4. Export your configurations
./config-manager.sh export

# 5. Review changes
git status
git diff

# 6. Commit your configurations
git add .
git commit -m "Add realm configuration and SSH integration"

# 7. Later, apply to fresh environment
./build.sh
./config-manager.sh import
```

### Automatic Configuration Sync

Use the watch mode to automatically export configurations as you make changes:

```bash
# In one terminal - watch for changes
./config-manager.sh watch

# In another terminal - make configuration changes
ssh vagrant@localhost -p 2222
# or access Keycloak at http://localhost:8080
```

## Network Setup

- Docker Bridge Network: `172.20.0.0/16`
- Keycloak: `172.20.0.x:8080`
- Ubuntu SSHD: `172.20.0.x:22`
- Windows AD: Configure QEMU network to bridge with Docker network

## Network Access

### Local Network Connectivity

The services are configured to be accessible from your local network, not just localhost:

- **Keycloak**: Accessible on port 8080 from any device on your local network
- **SSH**: Accessible on port 2222 from any device on your local network
- **Ports bound to**: `0.0.0.0` (all network interfaces)

### Getting Network Information

Use the network information script to see access details:

```bash
# Show local IP and connection information
./network-info.sh

# Test connectivity from local network
./network-info.sh
```

### Firewall Configuration

If you can't access services from other devices, you may need to configure your firewall:

**Ubuntu/Debian (UFW):**
```bash
sudo ufw allow 8080/tcp comment 'Keycloak HTTP'
sudo ufw allow 8443/tcp comment 'Keycloak HTTPS'  
sudo ufw allow 2222/tcp comment 'SSH to Ubuntu container'
```

**CentOS/RHEL (firewalld):**
```bash
sudo firewall-cmd --add-port=8080/tcp --permanent
sudo firewall-cmd --add-port=8443/tcp --permanent
sudo firewall-cmd --add-port=2222/tcp --permanent
sudo firewall-cmd --reload
```

### Accessing from Different Devices

**From Windows:**
- Browse to: `http://YOUR_LOCAL_IP:8080`
- SSH: Use PuTTY or Windows SSH client to `YOUR_LOCAL_IP:2222`

**From macOS/Linux:**
- Browse to: `http://YOUR_LOCAL_IP:8080`
- SSH: `ssh vagrant@YOUR_LOCAL_IP -p 2222`

**From Mobile:**
- Browse to: `http://YOUR_LOCAL_IP:8080`

## Development

### Rebuilding Services

```bash
# Rebuild specific service
docker compose build ubuntu-sshd
docker compose up -d ubuntu-sshd

# Rebuild all
docker compose build
docker compose up -d
```

### Logs

```bash
# View all logs
docker compose logs -f

# View specific service logs
docker compose logs -f keycloak
docker compose logs -f ubuntu-sshd
```

### Cleanup

```bash
# Stop services
docker compose down

# Remove volumes (careful - this deletes data!)
docker compose down -v

# Remove images
docker compose down --rmi all
```

## Troubleshooting

### Common Issues

1. **Port Conflicts**: Ensure ports 8080, 2222, and 8443 are available
2. **Memory**: Ensure sufficient RAM for all services (recommend 8GB+)
3. **Network**: Check Docker network configuration for QEMU bridge

### Service Health Checks

```bash
# Check Keycloak health
curl http://localhost:8080/health

# Test SSH connection
ssh -o ConnectTimeout=5 vagrant@localhost -p 2222

# Check Docker network
docker network inspect hybrid-auth-lab_hybrid-auth-network
```

## Keycloak Setup and OAuth Configuration

### Quick Setup Guide

1. **Start the services**:
   ```bash
   ./build.sh
   ```

2. **Start Windows AD Server** (for LDAP integration):
   ```bash
   cd windows-ad-server
   ./start-vm.sh
   ```

3. **Setup LDAP connectivity**:
   ```bash
   ./setup-ad-ldap.sh detect    # Find AD server
   ./setup-ad-ldap.sh test AD_IP DOMAIN  # Test connectivity
   ```

4. **Access Keycloak Admin Console**: 
   - URL: http://localhost:8080 (or use `./network-info.sh` for network access)
   - Username: `admin`
   - Password: `admin_password`

5. **Follow the complete setup guide**:
   ```bash
   # Open the detailed configuration guide
   cat docs/keycloak-setup-guide.md
   
   # Or view in your browser/editor
   ```

### OAuth Device Flow Testing

After setting up your realm and OAuth client:

```bash
# Test device flow with bash script
cd examples
./test-device-flow.sh

# Or test with Node.js
node test-device-flow.js

# For network access, set your local IP
KEYCLOAK_URL=http://YOUR_LOCAL_IP:8080 ./test-device-flow.sh
```

### Key Configuration Steps

1. **Start Services**: Windows AD VM + Docker containers
2. **Configure LDAP**: Import AD users into Keycloak via LDAP
3. **Create Realm**: `hybrid-auth` (or your preferred name)
4. **Enable Device Flow**: Realm Settings → Advanced → OAuth 2.0 Device Authorization Grant
5. **Create OAuth Client**: `device-flow-client` with device flow enabled
6. **Test Integration**: Use provided scripts to verify setup

See `docs/keycloak-setup-guide.md` for detailed step-by-step instructions

## 6. Configure OAuth/PAM Authentication (Linux Client)

Configure the Ubuntu client to authenticate users via OAuth Device Flow with Keycloak:

```bash
# Connect to the Ubuntu client container
docker exec -it ubuntu-sshd-client bash

# Set up OAuth/PAM authentication
export KEYCLOAK_CLIENT_SECRET="your_client_secret_from_step_3"
/opt/scripts/setup-oauth-pam.sh setup

# Create OAuth users
oauth-create john.doe "John Doe" "john.doe@example.com"
oauth-create jane.smith "Jane Smith" "jane.smith@example.com"

# Test OAuth authentication
exit  # Exit container
ssh john.doe@localhost -p 2222
# Follow device flow instructions in browser
```

For detailed OAuth/PAM setup instructions, see [OAuth/PAM Setup Guide](docs/oauth-pam-setup-guide.md).

## 7. Test the Complete Authentication Flow

Test the complete hybrid authentication flow:

```bash
# 1. Test OAuth Device Flow directly
./examples/test-oauth-device-flow.sh john.doe

# 2. Test SSH login with OAuth
ssh john.doe@localhost -p 2222
# Follow device flow instructions
# Complete authentication in browser
# You should be logged into the Ubuntu client

# 3. Verify user session
whoami
pwd
cat ~/.oauth_welcome

# 4. Test with different users
ssh jane.smith@localhost -p 2222
```

The authentication flow works as follows:
1. User attempts SSH login to Ubuntu client
2. PAM triggers OAuth Device Flow authentication
3. User visits Keycloak URL and enters device code
4. User authenticates against AD (via LDAP) in Keycloak
5. Keycloak issues OAuth tokens
6. PAM validates tokens and creates user session
7. User is logged into Ubuntu client

## 8. Troubleshooting

## Understanding the OAuth Configuration

### OAuth Client Setup in Keycloak

The tutorial comes with a pre-configured OAuth client that demonstrates best practices:

**Client Configuration:**
- **Client ID**: `ssh-pam-client`
- **Client Secret**: `ssh-pam-client-secret-2024-hybrid-auth-lab`
- **Grant Types**: Authorization Code, Device Flow
- **Realm**: `hybrid-auth`

**Device Flow Specific Settings:**
```json
{
  "attributes": {
    "oauth2.device.authorization.grant.enabled": "true",
    "oauth2.device.code.lifespan": "600",
    "oauth2.device.polling.interval": "5"
  }
}
```

### Testing OAuth Device Flow Manually

Understanding the OAuth flow helps troubleshoot and customize the integration:

```bash
# Step 1: Request device authorization
curl -X POST -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=ssh-pam-client&client_secret=ssh-pam-client-secret-2024-hybrid-auth-lab" \
  "http://localhost:8080/realms/hybrid-auth/protocol/openid-connect/auth/device"

# Response contains:
# - device_code: for polling
# - user_code: for user entry
# - verification_uri: where user authenticates
# - expires_in: code lifetime
# - interval: polling frequency
```

```bash
# Step 2: User visits verification_uri and enters user_code
# Step 3: Poll for token
curl -X POST -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=<DEVICE_CODE>&client_id=ssh-pam-client&client_secret=ssh-pam-client-secret-2024-hybrid-auth-lab" \
  "http://localhost:8080/realms/hybrid-auth/protocol/openid-connect/token"
```

### Comprehensive OAuth Testing

```bash
# Automated OAuth integration test
./test-oauth-integration.sh
```

This script validates:
- ✅ Keycloak accessibility
- ✅ OAuth client authentication
- ✅ Device flow endpoint functionality
- ✅ SSH container OAuth configuration
- ✅ PAM integration scripts

### Pre-configured Users

- **Admin**: admin/admin (Keycloak admin user)
- **Test User**: testuser/testpass (for OAuth testing)

For detailed OAuth configuration information, see: [`docs/keycloak-client-secret-config.md`](docs/keycloak-client-secret-config.md)

## Tutorial Documentation

This project includes comprehensive tutorials and guides:

### Core Tutorials
- **[OAuth Device Flow Tutorial](docs/oauth-device-flow-tutorial.md)** - Complete guide to OAuth Device Flow for Linux services
- **[OAuth/PAM Setup Guide](docs/oauth-pam-setup-guide.md)** - Step-by-step PAM integration tutorial
- **[Keycloak Setup Guide](docs/keycloak-setup-guide.md)** - Configuring Keycloak for OAuth Device Flow

### Reference Documentation
- **[OAuth/PAM Features](docs/oauth-pam-features.md)** - Feature overview and capabilities
- **[Client Secret Configuration](docs/keycloak-client-secret-config.md)** - OAuth client setup details

### Learning Path

**For OAuth/PAM Beginners:**
1. Start with [OAuth Device Flow Tutorial](docs/oauth-device-flow-tutorial.md)
2. Follow [OAuth/PAM Setup Guide](docs/oauth-pam-setup-guide.md)
3. Experiment with the tutorial environment

**For Integration Developers:**
1. Review [Keycloak Setup Guide](docs/keycloak-setup-guide.md)
2. Study [Client Secret Configuration](docs/keycloak-client-secret-config.md)
3. Examine the configuration management workflow

**For Production Deployment:**
1. Understand all tutorials above
2. Review security considerations in each guide
3. Plan your deployment strategy using the tutorial as a foundation
