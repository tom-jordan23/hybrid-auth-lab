#!/bin/bash
set -e

echo "=== Hybrid Auth Lab Network Information ==="

# Function to get local IP address
get_local_ip() {
    # Try multiple methods to get the local IP
    local ip=""
    
    # Method 1: ip route (most reliable on Linux)
    if command -v ip &> /dev/null; then
        ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    fi
    
    # Method 2: hostname -I (backup)
    if [ -z "$ip" ] && command -v hostname &> /dev/null; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    
    # Method 3: ifconfig (fallback)
    if [ -z "$ip" ] && command -v ifconfig &> /dev/null; then
        ip=$(ifconfig | grep -E "inet ([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -v 127.0.0.1 | awk '{print $2}' | head -1)
    fi
    
    echo "$ip"
}

# Function to check if services are running
check_service_status() {
    echo "=== Service Status ==="
    
    if docker compose ps | grep -q "Up"; then
        echo "✓ Docker Compose services are running"
        docker compose ps
    else
        echo "✗ Docker Compose services are not running"
        echo "Run './build.sh' to start services"
        return 1
    fi
}

# Function to show network access information
show_network_info() {
    local local_ip="$1"
    
    echo ""
    echo "=== Network Access Information ==="
    echo ""
    echo "Local machine access:"
    echo "  Keycloak Admin Console: http://localhost:8080"
    echo "  SSH to Ubuntu client:   ssh vagrant@localhost -p 2222"
    echo ""
    
    if [ -n "$local_ip" ]; then
        echo "Local network access (from other devices):"
        echo "  Keycloak Admin Console: http://${local_ip}:8080"
        echo "  SSH to Ubuntu client:   ssh vagrant@${local_ip} -p 2222"
        echo ""
        echo "Your local IP address: ${local_ip}"
    else
        echo "Could not determine local IP address."
        echo "Please check your network configuration."
    fi
    
    echo ""
    echo "Default credentials:"
    echo "  Keycloak Admin: admin / admin_password"
    echo "  SSH User:       vagrant / SecureUser123!"
    echo "  SSH Root:       root / SecureRoot123!"
}

# Function to test network connectivity
test_connectivity() {
    local local_ip="$1"
    
    echo ""
    echo "=== Testing Network Connectivity ==="
    
    # Test Keycloak locally
    echo -n "Testing Keycloak (localhost)... "
    if curl -s -f http://localhost:8080/health/ready > /dev/null 2>&1; then
        echo "✓ OK"
    else
        echo "✗ Failed"
    fi
    
    # Test SSH locally
    echo -n "Testing SSH (localhost)... "
    if nc -z localhost 2222 2>/dev/null; then
        echo "✓ OK"
    else
        echo "✗ Failed"
    fi
    
    if [ -n "$local_ip" ]; then
        # Test Keycloak from local IP
        echo -n "Testing Keycloak (${local_ip})... "
        if curl -s -f http://${local_ip}:8080/health/ready > /dev/null 2>&1; then
            echo "✓ OK"
        else
            echo "✗ Failed"
        fi
        
        # Test SSH from local IP
        echo -n "Testing SSH (${local_ip})... "
        if nc -z ${local_ip} 2222 2>/dev/null; then
            echo "✓ OK"
        else
            echo "✗ Failed"
        fi
    fi
}

# Function to show firewall information
show_firewall_info() {
    echo ""
    echo "=== Firewall Information ==="
    
    # Check if ufw is installed and active
    if command -v ufw &> /dev/null; then
        echo "UFW (Uncomplicated Firewall) status:"
        sudo ufw status 2>/dev/null || echo "  Cannot check UFW status (may need sudo)"
        echo ""
        echo "If UFW is active and blocking connections, allow the ports:"
        echo "  sudo ufw allow 8080/tcp comment 'Keycloak HTTP'"
        echo "  sudo ufw allow 8443/tcp comment 'Keycloak HTTPS'"
        echo "  sudo ufw allow 2222/tcp comment 'SSH to Ubuntu container'"
    fi
    
    # Check if iptables rules might be blocking
    echo ""
    echo "If you have custom iptables rules, ensure these ports are allowed:"
    echo "  - TCP 8080 (Keycloak HTTP)"
    echo "  - TCP 8443 (Keycloak HTTPS)"
    echo "  - TCP 2222 (SSH)"
}

# Function to generate connection commands for different operating systems
show_connection_examples() {
    local local_ip="$1"
    
    if [ -z "$local_ip" ]; then
        return
    fi
    
    echo ""
    echo "=== Connection Examples from Other Devices ==="
    echo ""
    echo "From Windows:"
    echo "  # Open web browser to:"
    echo "  http://${local_ip}:8080"
    echo ""
    echo "  # SSH using PuTTY or Windows SSH:"
    echo "  ssh vagrant@${local_ip} -p 2222"
    echo ""
    echo "From macOS/Linux:"
    echo "  # Open web browser to:"
    echo "  http://${local_ip}:8080"
    echo ""
    echo "  # SSH from terminal:"
    echo "  ssh vagrant@${local_ip} -p 2222"
    echo ""
    echo "From mobile devices:"
    echo "  # Open web browser to:"
    echo "  http://${local_ip}:8080"
}

# Main execution
LOCAL_IP=$(get_local_ip)

echo "Detected local IP: ${LOCAL_IP:-"Could not detect"}"
echo ""

if ! check_service_status; then
    exit 1
fi

show_network_info "$LOCAL_IP"
test_connectivity "$LOCAL_IP"
show_firewall_info
show_connection_examples "$LOCAL_IP"

echo ""
echo "=== Additional Notes ==="
echo "- Ensure your host firewall allows connections on ports 8080, 8443, and 2222"
echo "- If connecting from other devices fails, check your router/network configuration"
echo "- For production use, consider setting up proper SSL certificates for Keycloak"
echo "- The Docker bridge network (172.20.0.0/16) is for internal container communication"
