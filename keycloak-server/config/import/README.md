# Sample Keycloak realm configuration
# This file demonstrates how to configure a realm for hybrid authentication

# Place your exported realm JSON files in this directory
# Files placed here will be available in the container at /opt/keycloak/data/import/

# To export a realm from Keycloak:
# 1. Access the admin console at http://localhost:8080
# 2. Select your realm
# 3. Go to Realm Settings > Action > Export
# 4. Save the JSON file to this directory
# 5. Run: docker compose restart keycloak

# To import realm configurations:
# Use the config-manager.sh script:
# ./config-manager.sh import keycloak
