#!/bin/bash
set -e

echo "=== Stopping Hybrid Auth Lab Services ==="

# Stop Docker services
echo "Stopping Docker services..."
docker compose down

echo ""
echo "Services stopped successfully."
echo ""
echo "To completely clean up (remove volumes and data):"
echo "  docker compose down -v"
echo ""
echo "To remove built images as well:"
echo "  docker compose down --rmi all"
