#!/bin/bash
# Quick update of SecretProviderClass - simpler version

set -e

echo "Quick SecretProviderClass Update"
echo "================================"
echo ""

# Check kubectl
if ! kubectl get secretproviderclass authmanager-azure-keyvault -n muzika &> /dev/null; then
    echo "ERROR: SecretProviderClass not found"
    exit 1
fi

# Get current values
CURRENT_KV=$(kubectl get secretproviderclass authmanager-azure-keyvault -n muzika -o jsonpath='{.spec.parameters.keyvaultName}')
echo "Current Key Vault: $CURRENT_KV"

# Get tenant ID
echo ""
echo "Getting tenant ID..."
TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null || echo "")
if [ -z "$TENANT_ID" ]; then
    echo "ERROR: Please login to Azure first: az login"
    exit 1
fi
echo "Tenant ID: $TENANT_ID"

# Check if Key Vault exists
echo ""
echo "Checking Key Vault..."
if ! az keyvault show --name "$CURRENT_KV" &> /dev/null; then
    echo "ERROR: Key Vault '$CURRENT_KV' not found!"
    echo ""
    echo "Available Key Vaults:"
    az keyvault list --query '[].{name:name,resourceGroup:resourceGroup}' -o table
    echo ""
    read -p "Enter correct Key Vault name: " KEYVAULT_NAME
    CURRENT_KV="$KEYVAULT_NAME"
fi

# Get managed identity type
echo ""
echo "Checking managed identity..."
RESOURCE_GROUP="${RESOURCE_GROUP:-Digeper}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-Digeper-aks}"

IDENTITY_TYPE=$(az aks show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$AKS_CLUSTER_NAME" \
    --query "identity.type" -o tsv 2>/dev/null || echo "None")

echo "Identity Type: $IDENTITY_TYPE"

if [ "$IDENTITY_TYPE" = "SystemAssigned" ]; then
    MANAGED_IDENTITY_CLIENT_ID=""
    echo "Using system-assigned identity (empty userAssignedIdentityID)"
elif [ "$IDENTITY_TYPE" = "UserAssigned" ]; then
    echo "User-assigned identity - need to get client ID"
    MANAGED_IDENTITY_CLIENT_ID=$(az aks show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AKS_CLUSTER_NAME" \
        --query "identity.userAssignedIdentities" -o json | jq -r 'to_entries[0].value.clientId' 2>/dev/null || echo "")
    if [ -z "$MANAGED_IDENTITY_CLIENT_ID" ] || [ "$MANAGED_IDENTITY_CLIENT_ID" = "null" ]; then
        read -p "Enter Managed Identity Client ID: " MANAGED_IDENTITY_CLIENT_ID
    fi
else
    MANAGED_IDENTITY_CLIENT_ID=""
    echo "Using empty (will try system-assigned)"
fi

echo "Managed Identity Client ID: ${MANAGED_IDENTITY_CLIENT_ID:-'(empty)'}"

# Update SecretProviderClass
echo ""
echo "Updating SecretProviderClass..."
kubectl patch secretproviderclass authmanager-azure-keyvault -n muzika --type='json' -p="[
  {\"op\": \"replace\", \"path\": \"/spec/parameters/tenantId\", \"value\": \"$TENANT_ID\"},
  {\"op\": \"replace\", \"path\": \"/spec/parameters/userAssignedIdentityID\", \"value\": \"$MANAGED_IDENTITY_CLIENT_ID\"},
  {\"op\": \"replace\", \"path\": \"/spec/parameters/keyvaultName\", \"value\": \"$CURRENT_KV\"}
]"

echo ""
echo "✓ SecretProviderClass updated!"
echo ""
echo "Next: Grant Key Vault access and restart pods"
echo "  PRINCIPAL_ID=\$(az aks show --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query 'identity.principalId' -o tsv)"
echo "  KEYVAULT_ID=\$(az keyvault show --name $CURRENT_KV --query 'id' -o tsv)"
echo "  az role assignment create --role 'Key Vault Secrets User' --assignee \$PRINCIPAL_ID --scope \$KEYVAULT_ID"
echo "  kubectl delete pods -n muzika -l app=authmanager"

