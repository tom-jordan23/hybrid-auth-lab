#!/bin/bash
set -e

echo "=== Configuration Export Script ==="

# Function to create backup with timestamp
create_backup() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "${file}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "Created backup: ${file}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
}

# Function to export Keycloak configurations
export_keycloak_config() {
    echo ""
    echo "=== Exporting Keycloak Configuration ==="
    
    # Create keycloak config directory if it doesn't exist
    mkdir -p keycloak-server/config/exported
    
    # Export realm configurations
    echo "Exporting realm configurations..."
    if docker-compose exec -T keycloak ls /opt/keycloak/data/import/ 2>/dev/null; then
        docker-compose exec -T keycloak tar -czf /tmp/keycloak-export.tar.gz -C /opt/keycloak/data . 2>/dev/null || true
        docker-compose cp keycloak:/tmp/keycloak-export.tar.gz ./keycloak-server/config/exported/ 2>/dev/null || true
    fi
    
    # Export using Keycloak admin CLI if available
    echo "Attempting to export realms via admin CLI..."
    docker-compose exec -T keycloak /opt/keycloak/bin/kc.sh export --dir /tmp/realm-export 2>/dev/null || echo "Note: Direct export not available, will use API method"
    
    # Copy any export files
    docker-compose cp keycloak:/tmp/realm-export ./keycloak-server/config/exported/ 2>/dev/null || true
    
    # Export current configuration files
    echo "Exporting Keycloak configuration files..."
    docker-compose exec -T keycloak tar -czf /tmp/conf-export.tar.gz -C /opt/keycloak/conf . 2>/dev/null || true
    docker-compose cp keycloak:/tmp/conf-export.tar.gz ./keycloak-server/config/ 2>/dev/null || true
    
    # Extract the configuration
    if [ -f "./keycloak-server/config/conf-export.tar.gz" ]; then
        cd keycloak-server/config/
        tar -xzf conf-export.tar.gz
        rm conf-export.tar.gz
        cd ../..
        echo "✓ Keycloak configurations exported to keycloak-server/config/"
    fi
}

# Function to export SSH/PAM configurations
export_sshd_config() {
    echo ""
    echo "=== Exporting Ubuntu SSHD Configuration ==="
    
    # Create directories
    mkdir -p linux-client/config/exported/{ssh,pam,sssd,krb5}
    
    # Export SSH configuration
    echo "Exporting SSH configuration..."
    docker-compose exec -T ubuntu-sshd cat /etc/ssh/sshd_config > linux-client/config/exported/ssh/sshd_config 2>/dev/null || true
    docker-compose exec -T ubuntu-sshd cat /etc/ssh/ssh_config > linux-client/config/exported/ssh/ssh_config 2>/dev/null || true
    
    # Export PAM configuration
    echo "Exporting PAM configuration..."
    docker-compose exec -T ubuntu-sshd tar -czf /tmp/pam-export.tar.gz -C /etc/pam.d . 2>/dev/null || true
    docker-compose cp ubuntu-sshd:/tmp/pam-export.tar.gz ./linux-client/config/exported/pam/ 2>/dev/null || true
    
    if [ -f "./linux-client/config/exported/pam/pam-export.tar.gz" ]; then
        cd linux-client/config/exported/pam/
        tar -xzf pam-export.tar.gz
        rm pam-export.tar.gz
        cd ../../../..
    fi
    
    # Export SSSD configuration
    echo "Exporting SSSD configuration..."
    docker-compose exec -T ubuntu-sshd cat /etc/sssd/sssd.conf > linux-client/config/exported/sssd/sssd.conf 2>/dev/null || true
    
    # Export Kerberos configuration
    echo "Exporting Kerberos configuration..."
    docker-compose exec -T ubuntu-sshd cat /etc/krb5.conf > linux-client/config/exported/krb5/krb5.conf 2>/dev/null || true
    
    # Export NSS configuration
    echo "Exporting NSS configuration..."
    docker-compose exec -T ubuntu-sshd cat /etc/nsswitch.conf > linux-client/config/exported/nsswitch.conf 2>/dev/null || true
    
    # Export hosts and resolv.conf
    docker-compose exec -T ubuntu-sshd cat /etc/hosts > linux-client/config/exported/hosts 2>/dev/null || true
    docker-compose exec -T ubuntu-sshd cat /etc/resolv.conf > linux-client/config/exported/resolv.conf 2>/dev/null || true
    
    echo "✓ SSH/PAM configurations exported to linux-client/config/exported/"
}

# Function to show configuration status
show_config_status() {
    echo ""
    echo "=== Configuration Status ==="
    echo "Keycloak configurations:"
    find keycloak-server/config/ -name "*.conf" -o -name "*.json" -o -name "*.properties" 2>/dev/null | head -10 || echo "  No configuration files found"
    
    echo ""
    echo "SSH/PAM configurations:"
    find linux-client/config/exported/ -type f 2>/dev/null | head -10 || echo "  No configuration files found"
    
    echo ""
    echo "Recent exports:"
    find . -name "*.backup.*" -mtime -1 2>/dev/null | head -5 || echo "  No recent backups found"
}

# Main execution
if [ "$1" = "keycloak" ]; then
    export_keycloak_config
elif [ "$1" = "sshd" ] || [ "$1" = "ssh" ]; then
    export_sshd_config
elif [ "$1" = "status" ]; then
    show_config_status
elif [ "$1" = "all" ] || [ -z "$1" ]; then
    export_keycloak_config
    export_sshd_config
    show_config_status
else
    echo "Usage: $0 [keycloak|sshd|status|all]"
    echo "  keycloak - Export only Keycloak configurations"
    echo "  sshd     - Export only SSH/PAM configurations"
    echo "  status   - Show current configuration status"
    echo "  all      - Export all configurations (default)"
    exit 1
fi

echo ""
echo "=== Export Complete ==="
echo "Configuration files have been exported from running containers."
echo "Review the changes and commit them to git as needed."
