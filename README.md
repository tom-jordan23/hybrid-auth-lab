# Hybrid Authentication Lab

This project sets up a hybrid authentication environment with:
- **Keycloak Server** (Docker) - Identity and Access Management
- **Ubuntu SSHD Client** (Docker) - Linux client for testing authentication
- **Windows AD Server** (QEMU) - Active Directory Domain Controller

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Keycloak      │    │  Ubuntu SSHD    │    │  Windows AD     │
│   (Docker)      │    │  (Docker)       │    │  (QEMU VM)      │
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

## Quick Start

For a rapid setup of OAuth/PAM authentication:

```bash
# 1. Start the lab environment
./build.sh

# 2. Set up OAuth/PAM authentication (optional: set client secret)
export KEYCLOAK_CLIENT_SECRET="your_client_secret_from_keycloak"
./quick-start-oauth.sh setup

# 3. Test SSH login with OAuth
ssh testuser@localhost -p 2222
# Follow device flow instructions in browser
```

For detailed step-by-step setup, continue with the sections below.

## Detailed Setup

### 1. Start Docker Services

```bash
# Start Keycloak and Ubuntu SSHD servers
docker compose up -d

# Check status
docker compose ps
```

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

## Configuration Management

This project provides powerful tools for managing configurations between your git repository and running containers. This allows you to easily develop, test, and version control your Keycloak realm configurations and SSH/PAM settings.

### Configuration Workflow

1. **Start the services**: `./build.sh`
2. **Configure via UI/SSH**: Make changes in Keycloak admin console or SSH into the Ubuntu container
3. **Export configurations**: `./config-manager.sh export` 
4. **Review and commit**: Check the exported configs and commit to git
5. **Import to other environments**: `./config-manager.sh import`

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
docker exec -it ubuntu-client bash

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
