#!/bin/bash
# Key Vault Setup and Verification Script for AuthorizationManager
# This script verifies Key Vault configuration and optionally sets up secrets

set -e

echo "=========================================="
echo "Azure Key Vault Setup & Verification"
echo "=========================================="
echo ""

# Get configuration
read -p "Enter Azure Resource Group name: " RESOURCE_GROUP
read -p "Enter Key Vault name: " KEYVAULT_NAME
read -p "Enter AKS cluster name (optional, for managed identity check): " AKS_CLUSTER

echo ""
echo "Step 1: Checking Key Vault existence..."
echo ""

# Check if Key Vault exists
if ! az keyvault show --name "$KEYVAULT_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
  echo "❌ Key Vault '$KEYVAULT_NAME' not found in resource group '$RESOURCE_GROUP'"
  echo "   Create it with: az keyvault create --name $KEYVAULT_NAME --resource-group $RESOURCE_GROUP"
  exit 1
fi

echo "✅ Key Vault '$KEYVAULT_NAME' exists"
echo ""

# Required secrets
REQUIRED_SECRETS=("mysql-connection-string" "mysql-username" "mysql-password" "jwt-secret")

echo "Step 2: Checking required secrets..."
echo ""

MISSING_SECRETS=()
for secret in "${REQUIRED_SECRETS[@]}"; do
  if az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$secret" &>/dev/null; then
    echo "✅ Secret '$secret' exists"
    # Show value preview (first 20 chars)
    VALUE=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$secret" --query "value" -o tsv 2>/dev/null || echo "")
    if [ -n "$VALUE" ]; then
      PREVIEW="${VALUE:0:20}..."
      echo "   Preview: $PREVIEW"
    fi
  else
    echo "❌ Secret '$secret' is missing"
    MISSING_SECRETS+=("$secret")
  fi
done

echo ""

# Check MySQL connection string format
if [ -z "${MISSING_SECRETS[*]}" ] || [[ ! " ${MISSING_SECRETS[@]} " =~ " mysql-connection-string " ]]; then
  echo "Step 3: Verifying MySQL connection string format..."
  echo ""
  
  CONN_STRING=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "mysql-connection-string" --query "value" -o tsv 2>/dev/null || echo "")
  
  if [ -n "$CONN_STRING" ]; then
    # Check for SSL parameters
    if echo "$CONN_STRING" | grep -q "useSSL=true"; then
      echo "✅ Connection string includes SSL parameters"
    else
      echo "⚠️  Connection string missing SSL parameters"
      echo "   Current: ${CONN_STRING:0:50}..."
      echo ""
      read -p "Update connection string with SSL parameters? (y/n): " UPDATE_CONN
      if [ "$UPDATE_CONN" = "y" ]; then
        read -p "Enter MySQL server hostname (e.g., server.mysql.database.azure.com): " MYSQL_HOST
        read -p "Enter database name (e.g., userdb): " DB_NAME
        
        NEW_CONN="jdbc:mysql://${MYSQL_HOST}:3306/${DB_NAME}?useSSL=true&requireSSL=true&verifyServerCertificate=false&serverTimezone=UTC&allowPublicKeyRetrieval=true&useUnicode=true&characterEncoding=UTF-8"
        
        az keyvault secret set \
          --vault-name "$KEYVAULT_NAME" \
          --name "mysql-connection-string" \
          --value "$NEW_CONN" \
          --output none
        
        echo "✅ Connection string updated with SSL parameters"
      fi
    fi
  fi
  echo ""
fi

# Check managed identity if AKS cluster provided
if [ -n "$AKS_CLUSTER" ]; then
  echo "Step 4: Checking managed identity permissions..."
  echo ""
  
  # Get AKS managed identity
  AKS_IDENTITY=$(az aks show \
    --name "$AKS_CLUSTER" \
    --resource-group "$RESOURCE_GROUP" \
    --query "identity" -o json 2>/dev/null || echo "")
  
  if [ -n "$AKS_IDENTITY" ] && [ "$AKS_IDENTITY" != "null" ]; then
    # Check if system-assigned or user-assigned
    IDENTITY_TYPE=$(echo "$AKS_IDENTITY" | grep -o '"type":"[^"]*"' | cut -d'"' -f4 || echo "")
    
    if [ "$IDENTITY_TYPE" = "SystemAssigned" ]; then
      IDENTITY_ID=$(echo "$AKS_IDENTITY" | grep -o '"principalId":"[^"]*"' | cut -d'"' -f4 || echo "")
      echo "✅ Found system-assigned managed identity"
      echo "   Principal ID: $IDENTITY_ID"
    elif [ "$IDENTITY_TYPE" = "UserAssigned" ] || [ "$IDENTITY_TYPE" = "SystemAssigned,UserAssigned" ]; then
      echo "✅ Found user-assigned managed identity"
      # Get user-assigned identity client IDs
      CLIENT_IDS=$(echo "$AKS_IDENTITY" | grep -o '"clientId":"[^"]*"' | cut -d'"' -f4 || echo "")
      echo "   Client IDs: $CLIENT_IDS"
    fi
    
    # Check Key Vault access
    echo ""
    echo "Checking Key Vault access permissions..."
    KEYVAULT_ID="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEYVAULT_NAME"
    
    # Check for "Key Vault Secrets User" role
    ROLE_ASSIGNMENTS=$(az role assignment list \
      --scope "$KEYVAULT_ID" \
      --query "[?roleDefinitionName=='Key Vault Secrets User'].{Principal:principalId,Role:roleDefinitionName}" \
      -o table 2>/dev/null || echo "")
    
    if [ -n "$ROLE_ASSIGNMENTS" ] && echo "$ROLE_ASSIGNMENTS" | grep -q "Key Vault Secrets User"; then
      echo "✅ Managed identity has 'Key Vault Secrets User' role"
    else
      echo "⚠️  Managed identity may not have 'Key Vault Secrets User' role"
      echo ""
      read -p "Grant 'Key Vault Secrets User' role to managed identity? (y/n): " GRANT_ROLE
      if [ "$GRANT_ROLE" = "y" ]; then
        if [ "$IDENTITY_TYPE" = "SystemAssigned" ] && [ -n "$IDENTITY_ID" ]; then
          az role assignment create \
            --role "Key Vault Secrets User" \
            --assignee "$IDENTITY_ID" \
            --scope "$KEYVAULT_ID" \
            --output none
          echo "✅ Role granted to system-assigned identity"
        elif [ -n "$CLIENT_IDS" ]; then
          for CLIENT_ID in $CLIENT_IDS; do
            az role assignment create \
              --role "Key Vault Secrets User" \
              --assignee "$CLIENT_ID" \
              --scope "$KEYVAULT_ID" \
              --output none
            echo "✅ Role granted to user-assigned identity: $CLIENT_ID"
          done
        fi
      fi
    fi
  else
    echo "⚠️  Could not determine AKS managed identity"
  fi
  echo ""
fi

# Summary
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""

if [ ${#MISSING_SECRETS[@]} -eq 0 ]; then
  echo "✅ All required secrets are present"
else
  echo "❌ Missing secrets: ${MISSING_SECRETS[*]}"
  echo ""
  echo "Create missing secrets with:"
  for secret in "${MISSING_SECRETS[@]}"; do
    echo "  az keyvault secret set --vault-name $KEYVAULT_NAME --name $secret --value '<your-value>'"
  done
fi

echo ""
echo "Next steps:"
echo "1. Ensure all secrets are set in Key Vault"
echo "2. Verify managed identity has Key Vault access"
echo "3. Update SecretProviderClass with correct Key Vault name and managed identity client ID"
echo "4. Deploy AuthorizationManager: kubectl apply -k k8s/"
echo ""

