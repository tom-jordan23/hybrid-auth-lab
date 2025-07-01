# Getting Started with OAuth Device Flow for Linux SSH

## What This Tutorial Teaches

This project demonstrates how to modernize SSH authentication using **OAuth 2.0 Device Flow** instead of traditional passwords or SSH keys. You'll learn to integrate modern identity providers (like Keycloak) with traditional Linux services, optionally federated with Windows Active Directory.

## 🚀 Quick Start (5 minutes) - Docker Only

### 1. Start the Core Environment
```bash
git clone <this-repo>
cd hybrid-auth-lab
./build.sh

# Verify everything is working
./check-status.sh
```

### 2. Test OAuth Device Flow
```bash
./demo-oauth-device-flow.sh
```

This opens your browser and demonstrates the OAuth flow that SSH will use.

### 3. Try OAuth SSH Login
```bash
ssh testuser@localhost -p 2222
```

When prompted:
1. Note the verification URL and code
2. Open the URL in your browser  
3. Enter the code and login with: `testuser` / `testpass`
4. Your SSH session will be established!

## 🏢 Full Lab Setup (20 minutes) - With Windows AD

For the complete hybrid authentication experience including Windows Active Directory:

### Prerequisites
```bash
# Install required software (Ubuntu/Debian)
sudo apt install qemu-kvm qemu-system-x86 qemu-utils packer

# OR for Fedora/RHEL
sudo dnf install qemu-kvm qemu-system-x86 packer

# Add user to kvm group and relogin
sudo usermod -a -G kvm $USER
# Logout and login again
```

**System Requirements:**
- 8GB+ RAM (4GB for Windows VM)
- 20GB+ free disk space
- CPU with virtualization support

### Full Setup Steps
```bash
# 1. Start Docker components
./build.sh

# 2. Build Windows AD server (takes 15-20 minutes)
cd windows-ad-server
./build-vm.sh

# 3. Start Windows AD server
./start-vm.sh

# 4. Check complete status
cd .. && ./check-status.sh

# 5. Configure Keycloak to use Windows AD
./setup-ad-ldap.sh

# 6. Test complete integration
ssh windowsuser@localhost -p 2222
```

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
