#!/bin/bash
# Complete deployment script for AuthorizationManager
# This script handles Key Vault setup, SecretProviderClass update, and deployment

set -e

echo "=========================================="
echo "AuthorizationManager Deployment Script"
echo "=========================================="
echo ""

# Get configuration
read -p "Enter Azure Resource Group name: " RESOURCE_GROUP
read -p "Enter Key Vault name: " KEYVAULT_NAME
read -p "Enter AKS cluster name: " AKS_CLUSTER
read -p "Enter Azure Tenant ID (or press Enter to auto-detect): " TENANT_ID

# Auto-detect tenant ID if not provided
if [ -z "$TENANT_ID" ]; then
  TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null || echo "")
  if [ -z "$TENANT_ID" ]; then
    echo "❌ Could not auto-detect tenant ID. Please provide it manually."
    exit 1
  fi
  echo "✅ Auto-detected Tenant ID: $TENANT_ID"
fi

echo ""
echo "Step 1: Verifying Key Vault secrets..."
echo ""

REQUIRED_SECRETS=("mysql-connection-string" "mysql-username" "mysql-password" "jwt-secret")
MISSING_SECRETS=()

for secret in "${REQUIRED_SECRETS[@]}"; do
  if az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$secret" &>/dev/null; then
    echo "✅ Secret '$secret' exists"
  else
    echo "❌ Secret '$secret' is missing"
    MISSING_SECRETS+=("$secret")
  fi
done

if [ ${#MISSING_SECRETS[@]} -gt 0 ]; then
  echo ""
  echo "Missing secrets detected. Please create them:"
  for secret in "${MISSING_SECRETS[@]}"; do
    case $secret in
      "mysql-connection-string")
        read -p "Enter MySQL connection string (with SSL params): " MYSQL_CONN
        if [ -n "$MYSQL_CONN" ]; then
          az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$secret" --value "$MYSQL_CONN"
          echo "✅ Created secret '$secret'"
        fi
        ;;
      "mysql-username")
        read -p "Enter MySQL username: " MYSQL_USER
        if [ -n "$MYSQL_USER" ]; then
          az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$secret" --value "$MYSQL_USER"
          echo "✅ Created secret '$secret'"
        fi
        ;;
      "mysql-password")
        read -s -p "Enter MySQL password: " MYSQL_PASS
        echo ""
        if [ -n "$MYSQL_PASS" ]; then
          az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$secret" --value "$MYSQL_PASS"
          echo "✅ Created secret '$secret'"
        fi
        ;;
      "jwt-secret")
        read -s -p "Enter JWT secret (or press Enter to generate): " JWT_SECRET
        echo ""
        if [ -z "$JWT_SECRET" ]; then
          JWT_SECRET=$(openssl rand -base64 32)
          echo "Generated JWT secret"
        fi
        if [ -n "$JWT_SECRET" ]; then
          az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$secret" --value "$JWT_SECRET"
          echo "✅ Created secret '$secret'"
        fi
        ;;
    esac
  done
fi

echo ""
echo "Step 2: Verifying managed identity Key Vault access..."
echo ""

# Get AKS managed identity
echo "Retrieving AKS managed identity information..."
AKS_IDENTITY_JSON=$(az aks show \
  --name "$AKS_CLUSTER" \
  --resource-group "$RESOURCE_GROUP" \
  --query "identity" -o json 2>/dev/null || echo "{}")

if [ "$AKS_IDENTITY_JSON" = "{}" ] || [ -z "$AKS_IDENTITY_JSON" ]; then
  echo "❌ Could not retrieve AKS managed identity"
  echo "   Make sure the AKS cluster exists and you have proper permissions"
  exit 1
fi

# Determine identity type and get client ID
IDENTITY_TYPE=$(echo "$AKS_IDENTITY_JSON" | grep -o '"type":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
MANAGED_IDENTITY_CLIENT_ID=""

echo "   Identity JSON: $AKS_IDENTITY_JSON"
echo "   Detected type: $IDENTITY_TYPE"

if [ "$IDENTITY_TYPE" = "SystemAssigned" ]; then
  # For system-assigned, use principalId
  MANAGED_IDENTITY_CLIENT_ID=$(echo "$AKS_IDENTITY_JSON" | grep -o '"principalId":"[^"]*"' | cut -d'"' -f4 || echo "")
  if [ -z "$MANAGED_IDENTITY_CLIENT_ID" ]; then
    # Try alternative JSON path
    MANAGED_IDENTITY_CLIENT_ID=$(az aks show \
      --name "$AKS_CLUSTER" \
      --resource-group "$RESOURCE_GROUP" \
      --query "identity.principalId" -o tsv 2>/dev/null || echo "")
  fi
  echo "✅ Found system-assigned managed identity"
  echo "   Principal ID: $MANAGED_IDENTITY_CLIENT_ID"
elif [ "$IDENTITY_TYPE" = "UserAssigned" ]; then
  # For user-assigned, get clientId from userAssignedIdentities
  MANAGED_IDENTITY_CLIENT_ID=$(az aks show \
    --name "$AKS_CLUSTER" \
    --resource-group "$RESOURCE_GROUP" \
    --query "identity.userAssignedIdentities.*.clientId" -o tsv 2>/dev/null | head -1 || echo "")
  echo "✅ Found user-assigned managed identity"
  echo "   Client ID: $MANAGED_IDENTITY_CLIENT_ID"
elif [ "$IDENTITY_TYPE" = "SystemAssigned,UserAssigned" ] || echo "$IDENTITY_TYPE" | grep -q "UserAssigned"; then
  # For mixed, prefer user-assigned
  MANAGED_IDENTITY_CLIENT_ID=$(az aks show \
    --name "$AKS_CLUSTER" \
    --resource-group "$RESOURCE_GROUP" \
    --query "identity.userAssignedIdentities.*.clientId" -o tsv 2>/dev/null | head -1 || echo "")
  if [ -z "$MANAGED_IDENTITY_CLIENT_ID" ]; then
    # Fallback to system-assigned
    MANAGED_IDENTITY_CLIENT_ID=$(az aks show \
      --name "$AKS_CLUSTER" \
      --resource-group "$RESOURCE_GROUP" \
      --query "identity.principalId" -o tsv 2>/dev/null || echo "")
  fi
  echo "✅ Found managed identity (mixed or user-assigned)"
  echo "   Client ID: $MANAGED_IDENTITY_CLIENT_ID"
else
  echo "⚠️  Could not determine identity type from: $IDENTITY_TYPE"
  echo "   Attempting to get identity information directly..."
  
  # Try to get user-assigned identity first
  MANAGED_IDENTITY_CLIENT_ID=$(az aks show \
    --name "$AKS_CLUSTER" \
    --resource-group "$RESOURCE_GROUP" \
    --query "identity.userAssignedIdentities.*.clientId" -o tsv 2>/dev/null | head -1 || echo "")
  
  # If not found, try system-assigned
  if [ -z "$MANAGED_IDENTITY_CLIENT_ID" ]; then
    MANAGED_IDENTITY_CLIENT_ID=$(az aks show \
      --name "$AKS_CLUSTER" \
      --resource-group "$RESOURCE_GROUP" \
      --query "identity.principalId" -o tsv 2>/dev/null || echo "")
  fi
  
  if [ -z "$MANAGED_IDENTITY_CLIENT_ID" ]; then
    echo "❌ Could not determine managed identity client ID"
    echo "   Please provide it manually:"
    read -p "Enter managed identity client ID: " MANAGED_IDENTITY_CLIENT_ID
    if [ -z "$MANAGED_IDENTITY_CLIENT_ID" ]; then
      echo "❌ Managed identity client ID is required"
      exit 1
    fi
  else
    echo "✅ Found managed identity client ID: $MANAGED_IDENTITY_CLIENT_ID"
  fi
fi

if [ -z "$MANAGED_IDENTITY_CLIENT_ID" ]; then
  echo "❌ Could not determine managed identity client ID"
  echo "   Please provide it manually:"
  read -p "Enter managed identity client ID: " MANAGED_IDENTITY_CLIENT_ID
  if [ -z "$MANAGED_IDENTITY_CLIENT_ID" ]; then
    exit 1
  fi
fi

# Check Key Vault access
KEYVAULT_ID="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEYVAULT_NAME"

echo ""
echo "Checking Key Vault access permissions..."
ROLE_CHECK=$(az role assignment list \
  --scope "$KEYVAULT_ID" \
  --assignee "$MANAGED_IDENTITY_CLIENT_ID" \
  --query "[?roleDefinitionName=='Key Vault Secrets User']" -o json 2>/dev/null || echo "[]")

if echo "$ROLE_CHECK" | grep -q "Key Vault Secrets User"; then
  echo "✅ Managed identity has 'Key Vault Secrets User' role"
else
  echo "⚠️  Managed identity does not have 'Key Vault Secrets User' role"
  read -p "Grant 'Key Vault Secrets User' role? (y/n): " GRANT_ROLE
  if [ "$GRANT_ROLE" = "y" ]; then
    az role assignment create \
      --role "Key Vault Secrets User" \
      --assignee "$MANAGED_IDENTITY_CLIENT_ID" \
      --scope "$KEYVAULT_ID" \
      --output none
    echo "✅ Role granted"
  else
    echo "⚠️  Skipping role assignment. Deployment may fail if identity lacks permissions."
  fi
fi

echo ""
echo "Step 3: Updating SecretProviderClass..."
echo ""

# Update SecretProviderClass with actual values
SECRETPROVIDERCLASS_FILE="secretproviderclass.yaml"

if [ ! -f "$SECRETPROVIDERCLASS_FILE" ]; then
  echo "❌ SecretProviderClass file not found: $SECRETPROVIDERCLASS_FILE"
  exit 1
fi

# Create a backup
cp "$SECRETPROVIDERCLASS_FILE" "${SECRETPROVIDERCLASS_FILE}.backup"

# Replace placeholders
sed -i.bak "s|\${KEYVAULT_NAME}|$KEYVAULT_NAME|g" "$SECRETPROVIDERCLASS_FILE"
sed -i.bak "s|\${TENANT_ID}|$TENANT_ID|g" "$SECRETPROVIDERCLASS_FILE"

# For system-assigned identity, leave userAssignedIdentityID empty
# For user-assigned identity, use the client ID
if [ "$IDENTITY_TYPE" = "SystemAssigned" ]; then
  echo "   Using system-assigned identity (leaving userAssignedIdentityID empty)"
  sed -i.bak "s|userAssignedIdentityID: \"\${MANAGED_IDENTITY_CLIENT_ID}\"|userAssignedIdentityID: \"\"|g" "$SECRETPROVIDERCLASS_FILE"
else
  echo "   Using user-assigned identity: $MANAGED_IDENTITY_CLIENT_ID"
  sed -i.bak "s|\${MANAGED_IDENTITY_CLIENT_ID}|$MANAGED_IDENTITY_CLIENT_ID|g" "$SECRETPROVIDERCLASS_FILE"
fi

# Remove backup files
rm -f "${SECRETPROVIDERCLASS_FILE}.bak"

echo "✅ SecretProviderClass updated:"
echo "   Key Vault: $KEYVAULT_NAME"
echo "   Tenant ID: $TENANT_ID"
echo "   Managed Identity Client ID: $MANAGED_IDENTITY_CLIENT_ID"

echo ""
echo "Step 4: Deploying AuthorizationManager..."
echo ""

# Check if kubectl is configured
if ! kubectl cluster-info &>/dev/null; then
  echo "⚠️  kubectl not configured. Getting AKS credentials..."
  az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER" --overwrite-existing
fi

# Delete existing SecretProviderClass if it exists to avoid update conflicts
echo "Cleaning up existing SecretProviderClass..."
kubectl delete secretproviderclass authmanager-azure-keyvault -n muzika --ignore-not-found=true
sleep 2

# Check if Deployment exists
if kubectl get deployment authmanager -n muzika &>/dev/null; then
  echo "✅ Existing Deployment found. Will update it (keeping existing pods running)..."
else
  echo "ℹ️  No existing Deployment found. Will create a new one."
fi

# Apply all manifests (this will update existing Deployment or create new one)
echo "Applying Kubernetes manifests..."
APPLY_OUTPUT=$(kubectl apply -k . 2>&1)
APPLY_EXIT_CODE=$?
echo "$APPLY_OUTPUT"

# Only handle immutable selector error if it actually occurs
if [ $APPLY_EXIT_CODE -ne 0 ]; then
  if echo "$APPLY_OUTPUT" | grep -q "field is immutable" && echo "$APPLY_OUTPUT" | grep -q "spec.selector"; then
    echo ""
    echo "⚠️  Deployment selector is immutable. This is a rare case where selector changed."
    echo "   You'll need to manually delete the Deployment if you want to change the selector."
    echo "   For now, the Deployment will remain with its current selector."
    echo ""
    read -p "Delete and recreate Deployment with new selector? (y/n): " RECREATE
    if [ "$RECREATE" = "y" ]; then
      echo "Deleting existing Deployment..."
      kubectl delete deployment authmanager -n muzika --ignore-not-found=true
      echo "Waiting for Deployment to be fully deleted..."
      kubectl wait --for=delete deployment/authmanager -n muzika --timeout=60s 2>/dev/null || true
      sleep 3
      echo "Retrying apply after Deployment deletion..."
      kubectl apply -k .
    else
      echo "⚠️  Keeping existing Deployment. Some changes may not be applied."
    fi
  else
    echo "❌ Apply failed for a different reason. Exiting."
    exit $APPLY_EXIT_CODE
  fi
fi

# Apply SecretProviderClass separately
echo "Applying SecretProviderClass..."
kubectl apply -f "$SECRETPROVIDERCLASS_FILE"

# Wait for deployment
echo ""
echo "Waiting for deployment to be ready..."
kubectl rollout status deployment/authmanager -n muzika --timeout=300s

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Check pod status:"
echo "  kubectl get pods -n muzika -l app=authmanager"
echo ""
echo "Check logs:"
echo "  kubectl logs -f deployment/authmanager -n muzika"
echo ""
echo "Check service:"
echo "  kubectl get svc -n muzika authmanager"
echo ""

