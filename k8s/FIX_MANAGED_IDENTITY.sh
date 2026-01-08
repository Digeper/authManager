#!/bin/bash
# Fix managed identity assignment for Key Vault access

set -e

RESOURCE_GROUP="${RESOURCE_GROUP:-Digeper}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-Digeper-aks}"
KEYVAULT_NAME="${KEYVAULT_NAME}"

if [ -z "$KEYVAULT_NAME" ]; then
    echo "Usage: $0 <KEYVAULT_NAME>"
    echo ""
    echo "Example:"
    echo "  $0 my-keyvault"
    echo ""
    echo "Or set KEYVAULT_NAME environment variable"
    exit 1
fi

echo "========================================="
echo "  Fix Managed Identity for Key Vault"
echo "========================================="
echo ""

# Check if logged in
if ! az account show &> /dev/null; then
    echo "ERROR: Please login to Azure first: az login"
    exit 1
fi

echo "1. Getting AKS cluster managed identity..."
echo "=========================================="

# Get cluster identity
CLUSTER_IDENTITY=$(az aks show \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --query "identity" -o json)

IDENTITY_TYPE=$(echo "$CLUSTER_IDENTITY" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)
PRINCIPAL_ID=$(echo "$CLUSTER_IDENTITY" | grep -o '"principalId": "[^"]*"' | cut -d'"' -f4)

echo "Identity Type: $IDENTITY_TYPE"
echo "Principal ID: $PRINCIPAL_ID"
echo ""

if [ -z "$PRINCIPAL_ID" ]; then
    echo "ERROR: Could not find managed identity principal ID"
    echo ""
    echo "Your cluster might not have a managed identity enabled."
    echo "Enable it with:"
    echo "  az aks update --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --enable-managed-identity"
    exit 1
fi

echo "2. Getting Key Vault details..."
echo "=============================="

KEYVAULT_RG=$(az keyvault show \
    --name $KEYVAULT_NAME \
    --query "resourceGroup" -o tsv 2>/dev/null || echo "")

if [ -z "$KEYVAULT_RG" ]; then
    echo "ERROR: Key Vault '$KEYVAULT_NAME' not found"
    echo ""
    echo "List available Key Vaults:"
    az keyvault list --query "[].{name:name,resourceGroup:resourceGroup}" -o table
    exit 1
fi

KEYVAULT_ID=$(az keyvault show \
    --name $KEYVAULT_NAME \
    --resource-group $KEYVAULT_RG \
    --query "id" -o tsv)

echo "Key Vault Resource Group: $KEYVAULT_RG"
echo "Key Vault ID: $KEYVAULT_ID"
echo ""

echo "3. Checking current Key Vault access..."
echo "========================================"

EXISTING_ACCESS=$(az role assignment list \
    --assignee $PRINCIPAL_ID \
    --scope $KEYVAULT_ID \
    --query "[?roleDefinitionName=='Key Vault Secrets User'].{role:roleDefinitionName,principalId:principalId}" -o json 2>/dev/null || echo "[]")

if echo "$EXISTING_ACCESS" | grep -q "Key Vault Secrets User"; then
    echo "✓ Managed identity already has 'Key Vault Secrets User' role"
else
    echo "✗ Managed identity does NOT have Key Vault access"
    echo ""
    echo "4. Granting Key Vault access..."
    echo "==============================="
    
    az role assignment create \
        --role "Key Vault Secrets User" \
        --assignee $PRINCIPAL_ID \
        --scope $KEYVAULT_ID
    
    echo ""
    echo "✓ Access granted!"
fi

echo ""
echo "========================================="
echo "  Verification"
echo "========================================="
echo ""

echo "Checking access again..."
az role assignment list \
    --assignee $PRINCIPAL_ID \
    --scope $KEYVAULT_ID \
    --query "[].{role:roleDefinitionName,principalId:principalId}" -o table

echo ""
echo "========================================="
echo "  Next Steps"
echo "========================================="
echo ""
echo "1. Make sure SecretProviderClass has correct managed identity ID"
echo "   Check AuthorizationManager/k8s/secret.yaml"
echo ""
echo "2. Restart pods to pick up the identity:"
echo "   kubectl delete pods -n muzika -l app=authmanager"
echo ""
echo "If using user-assigned identity, also verify the identity client ID in SecretProviderClass"

