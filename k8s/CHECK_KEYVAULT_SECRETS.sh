#!/bin/bash
# Check and fix Key Vault secrets

set -e

KEYVAULT_NAME="${1:-digeper}"

echo "========================================="
echo "  Check Key Vault Secrets"
echo "========================================="
echo ""

# Check if logged in
if ! az account show &> /dev/null; then
    echo "ERROR: Please login to Azure first: az login"
    exit 1
fi

echo "Key Vault: $KEYVAULT_NAME"
echo ""

echo "1. Checking existing secrets..."
echo "================================"

SECRETS=$(az keyvault secret list --vault-name $KEYVAULT_NAME --query "[].name" -o tsv 2>/dev/null || echo "")

if [ -z "$SECRETS" ]; then
    echo "⚠ No secrets found in Key Vault"
    echo ""
    echo "Required secrets:"
    echo "  - mysql-connection-string"
    echo "  - mysql-username"
    echo "  - mysql-password"
    echo "  - jwt-secret"
    echo ""
    read -p "Create these secrets now? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "Creating secrets..."
        echo ""
        
        read -p "MySQL Server (e.g., myserver.mysql.database.azure.com): " MYSQL_SERVER
        read -p "MySQL Database name: " MYSQL_DB
        read -p "MySQL Username: " MYSQL_USER
        read -sp "MySQL Password: " MYSQL_PASS
        echo ""
        read -sp "JWT Secret (at least 256 bits): " JWT_SECRET
        echo ""
        
        # Create connection string
        MYSQL_URL="jdbc:mysql://${MYSQL_SERVER}:3306/${MYSQL_DB}?useSSL=true&requireSSL=true&serverTimezone=UTC&allowPublicKeyRetrieval=true"
        
        echo ""
        echo "Storing secrets in Key Vault..."
        az keyvault secret set --vault-name $KEYVAULT_NAME --name mysql-connection-string --value "$MYSQL_URL"
        az keyvault secret set --vault-name $KEYVAULT_NAME --name mysql-username --value "$MYSQL_USER"
        az keyvault secret set --vault-name $KEYVAULT_NAME --name mysql-password --value "$MYSQL_PASS"
        az keyvault secret set --vault-name $KEYVAULT_NAME --name jwt-secret --value "$JWT_SECRET"
        
        echo ""
        echo "✓ Secrets created!"
    fi
else
    echo "Found secrets:"
    echo "$SECRETS" | while read SECRET; do
        echo "  - $SECRET"
    done
    echo ""
    
    echo "2. Checking secret values..."
    echo "============================"
    
    REQUIRED_SECRETS=("mysql-connection-string" "mysql-username" "mysql-password" "jwt-secret")
    
    for SECRET_NAME in "${REQUIRED_SECRETS[@]}"; do
        if echo "$SECRETS" | grep -q "^${SECRET_NAME}$"; then
            VALUE=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $SECRET_NAME --query "value" -o tsv 2>/dev/null || echo "")
            if [ -z "$VALUE" ]; then
                echo "✗ $SECRET_NAME: Not found or empty"
            elif echo "$VALUE" | grep -q "REPLACE_WITH"; then
                echo "⚠ $SECRET_NAME: Contains placeholder value"
                echo "   Current: $(echo $VALUE | cut -c1-50)..."
            else
                echo "✓ $SECRET_NAME: Has value"
            fi
        else
            echo "✗ $SECRET_NAME: Missing"
        fi
    done
    
    echo ""
    echo "3. Update secrets with placeholder values?"
    echo "=========================================="
    read -p "Update secrets that contain placeholders? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for SECRET_NAME in "${REQUIRED_SECRETS[@]}"; do
            if echo "$SECRETS" | grep -q "^${SECRET_NAME}$"; then
                VALUE=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $SECRET_NAME --query "value" -o tsv 2>/dev/null || echo "")
                if echo "$VALUE" | grep -q "REPLACE_WITH"; then
                    echo ""
                    echo "Updating $SECRET_NAME..."
                    case $SECRET_NAME in
                        mysql-connection-string)
                            read -p "MySQL Server (e.g., myserver.mysql.database.azure.com): " MYSQL_SERVER
                            read -p "MySQL Database name: " MYSQL_DB
                            NEW_VALUE="jdbc:mysql://${MYSQL_SERVER}:3306/${MYSQL_DB}?useSSL=true&requireSSL=true&serverTimezone=UTC&allowPublicKeyRetrieval=true"
                            ;;
                        mysql-username)
                            read -p "MySQL Username: " NEW_VALUE
                            ;;
                        mysql-password)
                            read -sp "MySQL Password: " NEW_VALUE
                            echo ""
                            ;;
                        jwt-secret)
                            read -sp "JWT Secret: " NEW_VALUE
                            echo ""
                            ;;
                    esac
                    az keyvault secret set --vault-name $KEYVAULT_NAME --name $SECRET_NAME --value "$NEW_VALUE"
                    echo "✓ Updated"
                fi
            fi
        done
    fi
fi

echo ""
echo "========================================="
echo "  Next Steps"
echo "========================================="
echo ""
echo "After updating secrets, restart pods:"
echo "  kubectl delete pods -n muzika -l app=authmanager"
echo ""
echo "Monitor pod logs:"
echo "  kubectl logs -n muzika -l app=authmanager -f"

