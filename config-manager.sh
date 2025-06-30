#!/bin/bash
set -e

echo "=== Configuration Management Helper ==="

# Function to show available commands
show_help() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  export [service]     - Export configurations from running containers"
    echo "  import [service]     - Import configurations to running containers"
    echo "  edit <service>       - Open configuration directory for editing"
    echo "  backup              - Create backup of all configurations"
    echo "  restore <backup>    - Restore from backup"
    echo "  status              - Show configuration status"
    echo "  watch               - Watch for configuration changes and auto-export"
    echo ""
    echo "Services: keycloak, sshd, all"
    echo ""
    echo "Examples:"
    echo "  $0 export keycloak   - Export only Keycloak config"
    echo "  $0 import sshd       - Import SSH/PAM config"
    echo "  $0 edit keycloak     - Open Keycloak config directory"
    echo "  $0 watch             - Auto-export when configs change"
}

# Function to open configuration directory for editing
edit_config() {
    local service="$1"
    case "$service" in
        "keycloak")
            echo "Opening Keycloak configuration directory..."
            if command -v code &> /dev/null; then
                code keycloak-server/config/
            elif command -v vim &> /dev/null; then
                vim keycloak-server/config/
            else
                echo "Configuration directory: keycloak-server/config/"
                ls -la keycloak-server/config/
            fi
            ;;
        "sshd"|"ssh")
            echo "Opening SSH configuration directory..."
            if command -v code &> /dev/null; then
                code linux-client/config/
            elif command -v vim &> /dev/null; then
                vim linux-client/config/
            else
                echo "Configuration directory: linux-client/config/"
                ls -la linux-client/config/
            fi
            ;;
        *)
            echo "Unknown service: $service"
            echo "Available services: keycloak, sshd"
            exit 1
            ;;
    esac
}

# Function to backup configurations
backup_configs() {
    local backup_dir="backups/$(date +%Y%m%d_%H%M%S)"
    echo "Creating backup in: $backup_dir"
    
    mkdir -p "$backup_dir"
    
    # Backup Keycloak configs
    if [ -d "keycloak-server/config" ]; then
        cp -r keycloak-server/config "$backup_dir/keycloak-config"
    fi
    
    # Backup SSH configs
    if [ -d "linux-client/config" ]; then
        cp -r linux-client/config "$backup_dir/sshd-config"
    fi
    
    # Create backup manifest
    cat > "$backup_dir/manifest.txt" << EOF
Backup created: $(date)
Docker Compose version: $(docker-compose --version)
Keycloak container: $(docker-compose ps -q keycloak 2>/dev/null || echo "not running")
Ubuntu SSHD container: $(docker-compose ps -q ubuntu-sshd 2>/dev/null || echo "not running")
EOF
    
    echo "✓ Backup created: $backup_dir"
    ls -la "$backup_dir"
}

# Function to restore from backup
restore_configs() {
    local backup_dir="$1"
    
    if [ -z "$backup_dir" ]; then
        echo "Available backups:"
        ls -la backups/ 2>/dev/null || echo "No backups found"
        return 1
    fi
    
    if [ ! -d "$backup_dir" ]; then
        echo "Backup directory not found: $backup_dir"
        return 1
    fi
    
    echo "Restoring from backup: $backup_dir"
    
    # Restore Keycloak configs
    if [ -d "$backup_dir/keycloak-config" ]; then
        echo "Restoring Keycloak configuration..."
        rm -rf keycloak-server/config
        cp -r "$backup_dir/keycloak-config" keycloak-server/config
    fi
    
    # Restore SSH configs
    if [ -d "$backup_dir/sshd-config" ]; then
        echo "Restoring SSH configuration..."
        rm -rf linux-client/config
        cp -r "$backup_dir/sshd-config" linux-client/config
    fi
    
    echo "✓ Configuration restored from: $backup_dir"
    echo "Run './import-config.sh all' to apply to running containers"
}

# Function to watch for changes and auto-export
watch_configs() {
    echo "Watching for configuration changes in containers..."
    echo "Press Ctrl+C to stop watching"
    
    while true; do
        # Check if containers are running
        if docker-compose ps | grep -q "Up"; then
            # Export configurations silently
            ./export-config.sh all > /dev/null 2>&1
            
            # Check for git changes
            if git status --porcelain | grep -q "config\|\.conf\|\.json"; then
                echo "$(date): Configuration changes detected"
                git status --porcelain | grep "config\|\.conf\|\.json"
            fi
        fi
        
        sleep 30
    done
}

# Main execution
case "$1" in
    "export")
        ./export-config.sh "$2"
        ;;
    "import")
        ./import-config.sh "$2"
        ;;
    "edit")
        edit_config "$2"
        ;;
    "backup")
        backup_configs
        ;;
    "restore")
        restore_configs "$2"
        ;;
    "status")
        ./export-config.sh status
        ;;
    "watch")
        watch_configs
        ;;
    "help"|"-h"|"--help"|"")
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
