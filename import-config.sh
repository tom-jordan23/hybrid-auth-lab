#!/bin/bash
set -e

echo "=== Configuration Import Script ==="

# Function to import Keycloak configurations
import_keycloak_config() {
    echo ""
    echo "=== Importing Keycloak Configuration ==="
    
    # Check if configuration files exist
    if [ ! -d "keycloak-server/config" ]; then
        echo "No Keycloak configuration directory found."
        return 1
    fi
    
    # Import custom configuration files
    if [ -d "keycloak-server/config" ]; then
        echo "Copying configuration files to Keycloak container..."
        docker-compose cp keycloak-server/config/. keycloak:/opt/keycloak/conf/custom/ 2>/dev/null || true
        
        # Restart Keycloak to pick up new configurations
        echo "Restarting Keycloak to apply configurations..."
        docker-compose restart keycloak
        
        echo "✓ Keycloak configurations imported"
    fi
    
    # Import realm configurations if they exist
    if [ -d "keycloak-server/config/exported/realm-export" ]; then
        echo "Importing realm configurations..."
        docker-compose cp keycloak-server/config/exported/realm-export/. keycloak:/opt/keycloak/data/import/ 2>/dev/null || true
        echo "✓ Realm configurations copied to import directory"
        echo "Note: Restart Keycloak with --import-realm flag to import realms"
    fi
}

# Function to import SSH/PAM configurations
import_sshd_config() {
    echo ""
    echo "=== Importing Ubuntu SSHD Configuration ==="
    
    # Check if configuration files exist
    if [ ! -d "linux-client/config" ]; then
        echo "No SSH configuration directory found."
        return 1
    fi
    
    # Import SSH configuration
    if [ -f "linux-client/config/sshd_config" ]; then
        echo "Importing SSH configuration..."
        docker-compose cp linux-client/config/sshd_config ubuntu-sshd:/etc/ssh/sshd_config
        echo "✓ SSH configuration imported"
    fi
    
    # Import PAM configuration files
    if [ -d "linux-client/config/pam.d" ]; then
        echo "Importing PAM configuration..."
        docker-compose cp linux-client/config/pam.d/. ubuntu-sshd:/etc/pam.d/
        echo "✓ PAM configuration imported"
    fi
    
    # Import SSSD configuration
    if [ -f "linux-client/config/sssd.conf" ]; then
        echo "Importing SSSD configuration..."
        docker-compose cp linux-client/config/sssd.conf ubuntu-sshd:/etc/sssd/sssd.conf
        docker-compose exec ubuntu-sshd chmod 600 /etc/sssd/sssd.conf
        echo "✓ SSSD configuration imported"
    fi
    
    # Import Kerberos configuration
    if [ -f "linux-client/config/krb5.conf" ]; then
        echo "Importing Kerberos configuration..."
        docker-compose cp linux-client/config/krb5.conf ubuntu-sshd:/etc/krb5.conf
        echo "✓ Kerberos configuration imported"
    fi
    
    # Import NSS configuration
    if [ -f "linux-client/config/nsswitch.conf" ]; then
        echo "Importing NSS configuration..."
        docker-compose cp linux-client/config/nsswitch.conf ubuntu-sshd:/etc/nsswitch.conf
        echo "✓ NSS configuration imported"
    fi
    
    # Restart services to pick up new configurations
    echo "Restarting SSH and SSSD services..."
    docker-compose exec ubuntu-sshd service ssh restart 2>/dev/null || true
    docker-compose exec ubuntu-sshd service sssd restart 2>/dev/null || true
    
    echo "✓ SSH/PAM configurations imported and services restarted"
}

# Function to validate configurations
validate_configs() {
    echo ""
    echo "=== Validating Configurations ==="
    
    # Test SSH configuration
    echo "Testing SSH configuration..."
    if docker-compose exec ubuntu-sshd sshd -t 2>/dev/null; then
        echo "✓ SSH configuration is valid"
    else
        echo "✗ SSH configuration has errors"
    fi
    
    # Test SSSD configuration
    echo "Testing SSSD configuration..."
    if docker-compose exec ubuntu-sshd sssd --genconf-section=domain 2>/dev/null; then
        echo "✓ SSSD configuration appears valid"
    else
        echo "! SSSD configuration may have issues"
    fi
    
    # Check Keycloak health
    echo "Checking Keycloak health..."
    sleep 5
    if curl -s -f http://localhost:8080/health/ready > /dev/null 2>&1; then
        echo "✓ Keycloak is healthy"
    else
        echo "! Keycloak may be starting up or have issues"
    fi
}

# Main execution
if [ "$1" = "keycloak" ]; then
    import_keycloak_config
    validate_configs
elif [ "$1" = "sshd" ] || [ "$1" = "ssh" ]; then
    import_sshd_config
    validate_configs
elif [ "$1" = "all" ] || [ -z "$1" ]; then
    import_keycloak_config
    import_sshd_config
    validate_configs
else
    echo "Usage: $0 [keycloak|sshd|all]"
    echo "  keycloak - Import only Keycloak configurations"
    echo "  sshd     - Import only SSH/PAM configurations"
    echo "  all      - Import all configurations (default)"
    exit 1
fi

echo ""
echo "=== Import Complete ==="
echo "Configuration files have been imported to running containers."
echo "Services have been restarted to apply the changes."
