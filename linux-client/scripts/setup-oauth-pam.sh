#!/bin/bash
# Setup OAuth/PAM Authentication on Ubuntu Client
# This script configures the Ubuntu client for OAuth authentication via Keycloak

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config"
CLIENT_SECRET="${KEYCLOAK_CLIENT_SECRET:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Install required packages
install_packages() {
    log_info "Installing required packages..."
    
    apt update
    
    # Install essential packages
    apt install -y \
        curl \
        jq \
        libpam-modules \
        libpam-runtime \
        openssh-server \
        systemd
    
    log_success "Required packages installed"
}

# Setup OAuth authentication script
setup_oauth_script() {
    log_info "Setting up OAuth authentication script..."
    
    # Create auth directory
    mkdir -p /opt/auth
    
    # Copy OAuth script
    cp "$SCRIPT_DIR/oauth_auth.sh" /opt/auth/
    chmod +x /opt/auth/oauth_auth.sh
    
    # Create environment file for OAuth configuration
    cat > /etc/default/oauth-auth << EOF
# OAuth Authentication Configuration
KEYCLOAK_URL=http://keycloak:8080
KEYCLOAK_REALM=hybrid-auth
KEYCLOAK_CLIENT_ID=ssh-pam-client
KEYCLOAK_CLIENT_SECRET=${CLIENT_SECRET}
OAUTH_TIMEOUT=300
OAUTH_POLL_INTERVAL=5
EOF
    
    chmod 600 /etc/default/oauth-auth
    
    log_success "OAuth script configured"
}

# Configure PAM for SSH OAuth authentication
configure_pam() {
    log_info "Configuring PAM for OAuth authentication..."
    
    # Backup original PAM configuration
    if [[ ! -f /etc/pam.d/sshd.backup ]]; then
        cp /etc/pam.d/sshd /etc/pam.d/sshd.backup
        log_info "Backed up original PAM configuration"
    fi
    
    # Install OAuth PAM configuration
    cp "$CONFIG_DIR/pam-sshd-oauth.conf" /etc/pam.d/sshd
    
    log_success "PAM configured for OAuth authentication"
}

# Configure SSH daemon
configure_ssh() {
    log_info "Configuring SSH daemon for OAuth authentication..."
    
    # Backup original SSH configuration
    if [[ ! -f /etc/ssh/sshd_config.backup ]]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
        log_info "Backed up original SSH configuration"
    fi
    
    # Update SSH configuration
    cat >> /etc/ssh/sshd_config << 'EOF'

# OAuth/PAM Authentication Configuration
UsePAM yes
PasswordAuthentication yes
ChallengeResponseAuthentication yes
KbdInteractiveAuthentication yes
AuthenticationMethods keyboard-interactive
PubkeyAuthentication no
PermitRootLogin no
UseDNS no

# OAuth user settings
AllowUsers *
MaxAuthTries 3
LoginGraceTime 300
EOF
    
    log_success "SSH daemon configured for OAuth authentication"
}

# Create user management utilities
create_user_utilities() {
    log_info "Creating user management utilities..."
    
    # Create user management script
    cat > /opt/auth/manage_oauth_users.sh << 'EOF'
#!/bin/bash
# OAuth User Management Utilities

create_oauth_user() {
    local username="$1"
    local display_name="${2:-$username}"
    local email="${3:-}"
    
    if id "$username" &>/dev/null; then
        echo "User $username already exists"
        return 0
    fi
    
    echo "Creating OAuth user: $username"
    useradd -m -s /bin/bash -c "$display_name" "$username"
    
    # Set up home directory
    local home_dir="/home/$username"
    mkdir -p "$home_dir"
    chown "$username:$username" "$home_dir"
    chmod 755 "$home_dir"
    
    # Copy default files
    cp -r /etc/skel/. "$home_dir/" 2>/dev/null || true
    chown -R "$username:$username" "$home_dir"
    
    echo "Created OAuth user: $username ($display_name)"
}

list_oauth_users() {
    echo "OAuth-enabled users:"
    getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" {print $1 "\t" $5}' | sort
}

remove_oauth_user() {
    local username="$1"
    
    if ! id "$username" &>/dev/null; then
        echo "User $username does not exist"
        return 1
    fi
    
    read -p "Remove user $username and home directory? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        userdel -r "$username"
        echo "Removed user: $username"
    fi
}

# Command dispatch
case "${1:-}" in
    create)
        shift
        create_oauth_user "$@"
        ;;
    list)
        list_oauth_users
        ;;
    remove)
        shift
        remove_oauth_user "$@"
        ;;
    *)
        echo "Usage: $0 {create|list|remove} [args...]"
        echo ""
        echo "Commands:"
        echo "  create <username> [display_name] [email]  - Create OAuth user"
        echo "  list                                      - List OAuth users"
        echo "  remove <username>                         - Remove OAuth user"
        exit 1
        ;;
esac
EOF
    
    chmod +x /opt/auth/manage_oauth_users.sh
    
    # Create convenient aliases
    cat > /etc/profile.d/oauth-auth.sh << 'EOF'
# OAuth Authentication Aliases and Functions

alias oauth-users='/opt/auth/manage_oauth_users.sh list'
alias oauth-create='/opt/auth/manage_oauth_users.sh create'
alias oauth-remove='/opt/auth/manage_oauth_users.sh remove'

# Source OAuth environment
if [[ -f /etc/default/oauth-auth ]]; then
    source /etc/default/oauth-auth
fi
EOF
    
    log_success "User management utilities created"
}

# Setup systemd environment
setup_systemd_environment() {
    log_info "Setting up systemd environment..."
    
    # Create systemd environment file
    mkdir -p /etc/systemd/system/ssh.service.d
    
    cat > /etc/systemd/system/ssh.service.d/oauth-env.conf << 'EOF'
[Service]
EnvironmentFile=-/etc/default/oauth-auth
EOF
    
    systemctl daemon-reload
    
    log_success "Systemd environment configured"
}

# Validate configuration
validate_setup() {
    log_info "Validating OAuth setup..."
    
    local errors=0
    
    # Check OAuth script
    if [[ ! -x /opt/auth/oauth_auth.sh ]]; then
        log_error "OAuth authentication script not found or not executable"
        errors=$((errors + 1))
    fi
    
    # Check PAM configuration
    if [[ ! -f /etc/pam.d/sshd ]]; then
        log_error "PAM SSH configuration not found"
        errors=$((errors + 1))
    fi
    
    # Check environment file
    if [[ ! -f /etc/default/oauth-auth ]]; then
        log_error "OAuth environment file not found"
        errors=$((errors + 1))
    fi
    
    # Check client secret
    if [[ -z "$CLIENT_SECRET" ]]; then
        log_warning "KEYCLOAK_CLIENT_SECRET not set - you'll need to configure this manually"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "OAuth setup validation passed"
        return 0
    else
        log_error "OAuth setup validation failed with $errors errors"
        return 1
    fi
}

# Start services
start_services() {
    log_info "Starting services..."
    
    # Restart SSH service
    systemctl restart ssh
    
    # Check service status
    if systemctl is-active --quiet ssh; then
        log_success "SSH service is running"
    else
        log_error "SSH service failed to start"
        systemctl status ssh
        return 1
    fi
}

# Display setup information
show_setup_info() {
    echo ""
    log_success "OAuth/PAM setup completed!"
    echo ""
    echo "Configuration Summary:"
    echo "  - OAuth script: /opt/auth/oauth_auth.sh"
    echo "  - PAM config: /etc/pam.d/sshd"
    echo "  - SSH config: /etc/ssh/sshd_config"
    echo "  - Environment: /etc/default/oauth-auth"
    echo "  - User management: /opt/auth/manage_oauth_users.sh"
    echo ""
    echo "Next Steps:"
    echo "  1. Set KEYCLOAK_CLIENT_SECRET in /etc/default/oauth-auth"
    echo "  2. Create OAuth users: oauth-create <username>"
    echo "  3. Test SSH login: ssh <username>@localhost"
    echo ""
    echo "Useful Commands:"
    echo "  - oauth-users         # List OAuth users"
    echo "  - oauth-create user   # Create OAuth user"
    echo "  - oauth-remove user   # Remove OAuth user"
    echo ""
    
    if [[ -z "$CLIENT_SECRET" ]]; then
        echo ""
        log_warning "Remember to set the Keycloak client secret:"
        echo "  echo 'KEYCLOAK_CLIENT_SECRET=your_secret_here' >> /etc/default/oauth-auth"
        echo "  systemctl restart ssh"
    fi
}

# Restore original configuration
restore_original() {
    log_info "Restoring original configuration..."
    
    # Restore PAM configuration
    if [[ -f /etc/pam.d/sshd.backup ]]; then
        mv /etc/pam.d/sshd.backup /etc/pam.d/sshd
        log_info "Restored PAM configuration"
    fi
    
    # Restore SSH configuration
    if [[ -f /etc/ssh/sshd_config.backup ]]; then
        mv /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
        log_info "Restored SSH configuration"
    fi
    
    # Remove OAuth files
    rm -rf /opt/auth
    rm -f /etc/default/oauth-auth
    rm -f /etc/profile.d/oauth-auth.sh
    rm -rf /etc/systemd/system/ssh.service.d
    
    systemctl daemon-reload
    systemctl restart ssh
    
    log_success "Original configuration restored"
}

# Main function
main() {
    case "${1:-setup}" in
        setup)
            check_root
            install_packages
            setup_oauth_script
            configure_pam
            configure_ssh
            create_user_utilities
            setup_systemd_environment
            
            if validate_setup; then
                start_services
                show_setup_info
            else
                log_error "Setup validation failed"
                exit 1
            fi
            ;;
        
        restore)
            check_root
            restore_original
            ;;
        
        validate)
            validate_setup
            ;;
        
        help|--help|-h)
            echo "OAuth/PAM Setup Script"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  setup    - Setup OAuth/PAM authentication (default)"
            echo "  restore  - Restore original configuration"
            echo "  validate - Validate current setup"
            echo "  help     - Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  KEYCLOAK_CLIENT_SECRET - Keycloak client secret"
            ;;
        
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
