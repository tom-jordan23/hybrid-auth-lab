#!/bin/bash
set -e

echo "=== AD-Keycloak Network Setup Helper ==="

# Function to get Windows AD VM IP
get_ad_vm_ip() {
    echo "🔍 Looking for Windows AD server VM..."
    
    # Check if VM is running in QEMU
    local vm_pid=$(pgrep -f "qemu.*windows" || true)
    if [ -z "$vm_pid" ]; then
        echo "❌ Windows AD VM not found running"
        echo "Start it with: cd windows-ad-server && ./start-vm.sh"
        return 1
    fi
    
    echo "✅ Windows AD VM is running (PID: $vm_pid)"
    
    # Try to get IP from QEMU monitor or network interfaces
    # This is a placeholder - actual implementation depends on QEMU network setup
    echo "📡 Detecting VM network configuration..."
    
    # Common QEMU network ranges
    local common_ranges=("192.168.122.0/24" "10.0.2.0/24" "172.16.0.0/24")
    
    echo "🔍 Common QEMU network ranges to check:"
    for range in "${common_ranges[@]}"; do
        echo "   - $range"
    done
    
    echo ""
    echo "💡 To find your AD server IP:"
    echo "   1. Connect to Windows AD VM console"
    echo "   2. Run: ipconfig /all"
    echo "   3. Note the IPv4 address"
    echo "   4. Test connectivity from Ubuntu container:"
    echo "      ssh vagrant@localhost -p 2222"
    echo "      ping AD_SERVER_IP"
    echo "      telnet AD_SERVER_IP 389"
}

# Function to test LDAP connectivity
test_ldap_connectivity() {
    local ad_ip="$1"
    local domain="$2"
    
    if [ -z "$ad_ip" ] || [ -z "$domain" ]; then
        echo "❌ Missing AD IP or domain"
        echo "Usage: test_ldap_connectivity <AD_IP> <DOMAIN>"
        return 1
    fi
    
    echo "🧪 Testing LDAP connectivity to $ad_ip..."
    
    # Test from Ubuntu container
    echo "📡 Testing from Ubuntu SSHD container..."
    
    docker compose exec ubuntu-sshd bash -c "
        # Install LDAP utilities if not present
        apt-get update >/dev/null 2>&1
        apt-get install -y ldap-utils telnet >/dev/null 2>&1
        
        echo '🔌 Testing network connectivity...'
        if ping -c 3 $ad_ip >/dev/null 2>&1; then
            echo '✅ Ping successful'
        else
            echo '❌ Ping failed'
            exit 1
        fi
        
        echo '🔌 Testing LDAP port 389...'
        if timeout 5 telnet $ad_ip 389 >/dev/null 2>&1; then
            echo '✅ LDAP port 389 is open'
        else
            echo '❌ LDAP port 389 is not accessible'
            exit 1
        fi
        
        echo '🔍 Testing LDAP query...'
        # Basic LDAP search without authentication
        ldapsearch -x -H ldap://$ad_ip:389 -b '' -s base 2>/dev/null | head -5 || echo '⚠️  Anonymous LDAP query failed (this may be expected)'
        
        echo '✅ Basic connectivity tests completed'
    "
    
    if [ $? -eq 0 ]; then
        echo "✅ LDAP connectivity test passed"
        echo ""
        echo "📝 LDAP Configuration for Keycloak:"
        echo "   Connection URL: ldap://$ad_ip:389"
        echo "   Users DN: CN=Users,DC=$(echo $domain | sed 's/\./,DC=/g')"
        echo "   Bind DN: CN=Administrator,CN=Users,DC=$(echo $domain | sed 's/\./,DC=/g')"
        echo ""
    else
        echo "❌ LDAP connectivity test failed"
        return 1
    fi
}

# Function to configure Docker network for QEMU bridge
configure_network_bridge() {
    echo "🌉 Configuring network bridge for QEMU VM access..."
    
    # Check if bridge network exists
    if docker network ls | grep -q "qemu-bridge"; then
        echo "✅ QEMU bridge network already exists"
    else
        echo "🔧 Creating QEMU bridge network..."
        docker network create --driver bridge --subnet=192.168.100.0/24 qemu-bridge
    fi
    
    # Add containers to bridge network
    echo "🔗 Connecting containers to bridge network..."
    docker network connect qemu-bridge keycloak-server 2>/dev/null || echo "   Keycloak already connected"
    docker network connect qemu-bridge ubuntu-sshd-client 2>/dev/null || echo "   Ubuntu SSHD already connected"
    
    echo "✅ Network bridge configured"
    echo ""
    echo "📋 Next steps:"
    echo "   1. Configure your QEMU VM to use bridge networking"
    echo "   2. Set static IP in Windows AD server (e.g., 192.168.100.10)"
    echo "   3. Test connectivity with: ping 192.168.100.10"
}

# Function to show LDAP troubleshooting info
show_troubleshooting_info() {
    echo ""
    echo "🔧 LDAP Troubleshooting Guide:"
    echo ""
    echo "1. **Network Connectivity Issues:**"
    echo "   - Ensure Windows AD VM is running"
    echo "   - Check VM network configuration (bridge vs NAT)"
    echo "   - Verify firewall rules on Windows AD server"
    echo "   - Test with: ping AD_SERVER_IP"
    echo ""
    echo "2. **LDAP Port Access:**"
    echo "   - LDAP: port 389 (unencrypted)"
    echo "   - LDAPS: port 636 (SSL/TLS)"
    echo "   - Test with: telnet AD_SERVER_IP 389"
    echo ""
    echo "3. **Common Windows AD LDAP Settings:**"
    echo "   - Vendor: Active Directory"
    echo "   - Username attribute: sAMAccountName"
    echo "   - UUID attribute: objectGUID"
    echo "   - User object classes: person, organizationalPerson, user"
    echo ""
    echo "4. **Authentication Issues:**"
    echo "   - Use full DN for bind user: CN=Administrator,CN=Users,DC=domain,DC=com"
    echo "   - Ensure bind user has LDAP read permissions"
    echo "   - Check password complexity requirements"
    echo ""
    echo "5. **Container-to-VM Networking:**"
    echo "   - Use bridge networking for QEMU VM"
    echo "   - Ensure containers can reach VM network"
    echo "   - Consider static IP assignment for AD server"
}

# Main execution
case "$1" in
    "detect")
        get_ad_vm_ip
        ;;
    "test")
        test_ldap_connectivity "$2" "$3"
        ;;
    "bridge")
        configure_network_bridge
        ;;
    "troubleshoot"|"help")
        show_troubleshooting_info
        ;;
    *)
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  detect                    - Detect Windows AD VM"
        echo "  test <AD_IP> <DOMAIN>     - Test LDAP connectivity"
        echo "  bridge                    - Configure Docker bridge network"
        echo "  troubleshoot              - Show troubleshooting guide"
        echo ""
        echo "Examples:"
        echo "  $0 detect"
        echo "  $0 test 192.168.122.10 example.com"
        echo "  $0 bridge"
        echo "  $0 troubleshoot"
        echo ""
        show_troubleshooting_info
        ;;
esac
