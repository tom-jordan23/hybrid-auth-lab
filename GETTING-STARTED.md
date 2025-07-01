# Getting Started with OAuth Device Flow for Linux SSH

## What This Tutorial Teaches

This project demonstrates how to implement **OAuth 2.0 Device Flow** authentication for traditional Linux services like SSH, integrated with **Windows Active Directory** as the authentication source. You'll learn to create a complete hybrid authentication solution that bridges modern OAuth with traditional enterprise infrastructure.

## 🏢 Complete Hybrid Authentication (30 minutes)

This tutorial builds a complete enterprise authentication scenario:
- **Windows Active Directory** as the user store
- **Keycloak** as the OAuth 2.0 server with LDAP federation
- **Linux SSH** with OAuth Device Flow authentication
- **Group membership** claims from AD in OAuth tokens

### Prerequisites
```bash
# Install required software (Ubuntu/Debian)
sudo apt install docker.io docker-compose qemu-kvm qemu-system-x86 packer jq

# OR for Fedora/RHEL
sudo dnf install docker docker-compose qemu-kvm qemu-system-x86 packer jq

# Add user to required groups and relogin
sudo usermod -a -G docker,kvm $USER
# Logout and login again
```

**System Requirements:**
- 8GB+ RAM (4GB for Windows AD VM)
- 30GB+ free disk space  
- CPU with virtualization support

### Complete Setup (Build Windows AD First!)
```bash
# 1. Clone with submodules (includes Windows AD server)
git clone --recursive <this-repo>
cd hybrid-auth-lab

# If you already cloned without --recursive:
# git submodule update --init --recursive

# Make scripts executable
chmod +x *.sh windows-ad-server/*.sh

# 2. Build Windows AD Domain Controller FIRST (takes 15-20 minutes)
cd windows-ad-server
./build-vm.sh              # Build Windows Server 2022 with AD
./start-vm.sh               # Start domain controller  
./status.sh                 # Verify AD is running with LDAP
cd ..

# 3. Build OAuth components with AD integration (takes 5 minutes)
./build.sh                  # Automatically configures Keycloak LDAP federation

# 4. Verify complete setup
./status.sh                 # Quick overview
./check-status.sh           # Detailed if needed

# 5. Test hybrid authentication with Active Directory user
ssh Administrator@localhost -p 2222
# Use AD credentials in OAuth browser flow!
```

**Why Windows AD First?**
- Keycloak configures LDAP federation during startup
- AD provides users and groups for OAuth claims
- Demonstrates real enterprise authentication flow

## 🚀 Simplified Test (5 minutes) - OAuth Concepts Only

If you want to understand OAuth Device Flow concepts without building Windows AD:

**Note:** This skips Active Directory integration and uses local Keycloak test users instead.

### 1. Start Core Components Only
```bash
git clone --recursive <this-repo>
cd hybrid-auth-lab

# Start only Docker components (skips Windows AD requirement)
docker compose up -d

# Verify OAuth components
./test-oauth-integration.sh
```

### 2. Test OAuth Device Flow Concepts
```bash
./demo-oauth-device-flow.sh
```

### 3. Try OAuth SSH (with test users)
```bash
ssh testuser@localhost -p 2222
# Uses local Keycloak user: testuser/testpass
```

**Limitation:** This doesn't demonstrate real enterprise authentication or group claims from Active Directory.

## 🎯 What's Different About This Authentication?

### Traditional SSH
```
User → SSH → Server checks /etc/passwd → ✅/❌
```

### OAuth SSH (This Tutorial)
```
User → SSH → Server requests OAuth → Browser Auth → ✅/❌
```

**Benefits:**
- ✅ No passwords stored on SSH server
- ✅ Centralized user management
- ✅ Multi-factor authentication support
- ✅ Rich audit trails
- ✅ Integration with existing identity providers

## 🧠 Key Concepts You'll Learn

### OAuth 2.0 Device Flow
Perfect for SSH because:
- SSH servers don't have browsers
- Users can authenticate on their phones/laptops
- Supports rich authentication flows (MFA, SSO, etc.)

### Linux PAM Integration
- How PAM enables pluggable authentication
- Writing custom PAM modules
- Integrating OAuth with existing Linux infrastructure

### Keycloak as OAuth Server
- Setting up OAuth clients
- Configuring device flow
- User and session management

## 📚 Tutorial Structure

### Beginner Path
1. **Run Quick Start** (above) - See it working
2. **[OAuth Device Flow Tutorial](docs/oauth-device-flow-tutorial.md)** - Understand the concepts
3. **[OAuth/PAM Setup Guide](docs/oauth-pam-setup-guide.md)** - Learn the implementation

### Developer Path
1. **Quick Start** - Get familiar with the environment
2. **[Keycloak Setup Guide](docs/keycloak-setup-guide.md)** - OAuth server configuration
3. **Configuration Management** - Learn to customize and deploy

### Production Path
1. **All of the above**
2. **Security considerations** in each guide
3. **Scaling and deployment** planning

## 🔧 What's Included

### Pre-configured Components
- **Keycloak Server**: OAuth 2.0 server with device flow enabled
- **Ubuntu SSH Server**: SSH with OAuth PAM integration
- **OAuth Client**: Pre-configured for SSH authentication
- **Test Users**: Ready-to-use accounts for testing

### Scripts and Tools
- `./test-oauth-integration.sh` - Validate the OAuth setup
- `./demo-oauth-device-flow.sh` - Interactive OAuth demonstration
- `./config-manager.sh` - Manage configurations
- Development and deployment scripts

### Documentation
- Complete tutorial guides
- Configuration references
- Security best practices
- Troubleshooting guides

## 🎓 Learning Outcomes

After completing this tutorial, you'll understand:

**Technical Skills:**
- OAuth 2.0 Device Flow implementation
- Linux PAM module development
- Keycloak configuration and management
- SSH authentication customization

**Architectural Knowledge:**
- Modernizing legacy authentication systems
- Bridging traditional and modern infrastructure
- Security considerations for OAuth in enterprise environments
- Scalable identity management patterns

**Practical Applications:**
- Implementing centralized SSH authentication
- Integrating with existing identity providers
- Managing user access at scale
- Audit and compliance for Linux access

## 🔄 Next Steps

1. **Complete the Quick Start** to see OAuth SSH in action
2. **Read the tutorials** to understand the implementation
3. **Experiment with configuration** to learn customization
4. **Plan your deployment** using this as a foundation

The tutorial provides a complete foundation for implementing OAuth Device Flow authentication in production Linux environments.

## 🆘 Getting Help

- **Issues with setup?** Check the troubleshooting sections in each tutorial
- **Want to customize?** See the configuration management guides
- **Planning production deployment?** Review security considerations in the docs
- **Found a bug?** Please open an issue with details about your environment

This tutorial bridges the gap between traditional Linux infrastructure and modern identity management - start exploring!

## 🔧 Quick Troubleshooting

### Docker Issues
```bash
# Check if containers are running
docker compose ps

# View logs if something failed
docker compose logs keycloak-server
docker compose logs ubuntu-sshd-client

# Restart if needed
docker compose restart
```

### Windows VM Issues
```bash
# Check VM status
cd windows-ad-server && ./status.sh

# Check if QEMU/KVM is working
qemu-system-x86_64 --version
groups | grep kvm  # Should show kvm group

# Common fixes
sudo systemctl start libvirtd  # Start KVM service
sudo modprobe kvm-intel        # Load KVM module (Intel)
sudo modprobe kvm-amd          # Load KVM module (AMD)
```

### SSH OAuth Issues
```bash
# Test OAuth endpoint manually
curl -X POST -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=ssh-pam-client&client_secret=ssh-pam-client-secret-2024-hybrid-auth-lab" \
  "http://localhost:8080/realms/hybrid-auth/protocol/openid-connect/auth/device"

# Check if Keycloak is accessible
curl http://localhost:8080/realms/hybrid-auth/.well-known/openid_configuration
```

### Common Issues
- **"Port already in use"**: Stop other services using ports 8080, 2222, 3389
- **"Permission denied (kvm)"**: Add user to kvm group and relogin
- **"VM build fails"**: Check available disk space (need 20GB+)
- **"OAuth timeout"**: Check browser isn't blocking popups
