#!/bin/bash
# Quick Status Check for Hybrid Authentication Lab
# This provides a fast overview of all components

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Hybrid Authentication Lab - Quick Status ===${NC}"
echo ""

# Quick Docker check
echo -n "Docker Components: "
if docker compose ps >/dev/null 2>&1 && docker compose ps | grep -q "Up"; then
    echo -e "${GREEN}Running${NC}"
    DOCKER_STATUS="✅"
else
    echo -e "${RED}Not Running${NC}"
    DOCKER_STATUS="❌"
fi

# Quick Keycloak check
echo -n "Keycloak OAuth Server: "
if curl -s --connect-timeout 3 "http://localhost:8080/realms/hybrid-auth" >/dev/null 2>&1; then
    echo -e "${GREEN}Accessible${NC}"
    KEYCLOAK_STATUS="✅"
else
    echo -e "${RED}Not Accessible${NC}"
    KEYCLOAK_STATUS="❌"
fi

# Quick SSH check
echo -n "SSH Server (OAuth): "
if nc -z localhost 2222 2>/dev/null; then
    echo -e "${GREEN}Listening${NC}"
    SSH_STATUS="✅"
else
    echo -e "${RED}Not Listening${NC}"
    SSH_STATUS="❌"
fi

# Quick Windows AD check
echo -n "Windows AD Server: "
if [ -d "windows-ad-server" ] && [ -f "windows-ad-server/windows_2022_like_2019-qemu/WindowsServer2022-Like2019" ]; then
    if pgrep -f "WindowsServer2022-Like2019" >/dev/null; then
        if nc -z localhost 389 2>/dev/null; then
            echo -e "${GREEN}Running + LDAP Ready${NC}"
            AD_STATUS="✅"
        else
            echo -e "${YELLOW}Running (LDAP Starting)${NC}"
            AD_STATUS="⚠️"
        fi
    else
        echo -e "${RED}Not Running${NC}"
        AD_STATUS="❌"
    fi
else
    echo -e "${RED}Not Built${NC}"
    AD_STATUS="❌"
fi

echo ""

# Overall status
if [[ "$DOCKER_STATUS" == "✅" && "$KEYCLOAK_STATUS" == "✅" && "$SSH_STATUS" == "✅" && "$AD_STATUS" == "✅" ]]; then
    echo -e "${GREEN}🎉 Overall Status: READY FOR TESTING${NC}"
    echo ""
    echo "Try OAuth SSH authentication:"
    echo "  ssh Administrator@localhost -p 2222"
    echo ""
    echo "Test OAuth Device Flow:"
    echo "  ./demo-oauth-device-flow.sh"
elif [[ "$AD_STATUS" == "⚠️" ]]; then
    echo -e "${YELLOW}⏳ Overall Status: WAITING FOR AD SERVICES${NC}"
    echo ""
    echo "Windows AD is starting. Wait a few minutes and try again."
    echo "Check detailed AD status: cd windows-ad-server && ./status.sh"
else
    echo -e "${RED}🔧 Overall Status: SETUP REQUIRED${NC}"
    echo ""
    if [[ "$AD_STATUS" == "❌" ]]; then
        echo "Windows AD needs setup:"
        if [ ! -d "windows-ad-server" ]; then
            echo "  git submodule update --init --recursive"
        elif [ ! -f "windows-ad-server/windows_2022_like_2019-qemu/WindowsServer2022-Like2019" ]; then
            echo "  cd windows-ad-server && ./build-vm.sh"
        else
            echo "  cd windows-ad-server && ./start-vm.sh"
        fi
    fi
    if [[ "$DOCKER_STATUS" == "❌" || "$KEYCLOAK_STATUS" == "❌" ]]; then
        echo "OAuth components need setup:"
        echo "  ./build.sh"
    fi
fi

echo ""
echo -e "${BLUE}Detailed Status Commands:${NC}"
echo "  ./check-status.sh              - Complete lab status"
echo "  cd windows-ad-server && ./status.sh  - Windows AD details"
echo "  docker compose ps              - Docker container status"
echo "  ./test-oauth-integration.sh    - OAuth functionality test"
