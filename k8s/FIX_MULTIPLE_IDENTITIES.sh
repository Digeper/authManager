#!/bin/bash
# Fix multiple user-assigned identities issue

set -e

RESOURCE_GROUP="${RESOURCE_GROUP:-Digeper}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-Digeper-aks}"
KEYVAULT_NAME="${KEYVAULT_NAME:-digeper}"

echo "========================================="
echo "  Fix Multiple User-Assigned Identities"
echo "========================================="
echo ""

# Check if logged in
if ! az account show &> /dev/null; then
    echo "ERROR: Please login to Azure first: az login"
    exit 1
fi

echo "1. Getting AKS cluster identities..."
echo "====================================="

IDENTITIES=$(az aks show \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --query "identity.userAssignedIdentities" -o json)

IDENTITY_COUNT=$(echo "$IDENTITIES" | jq 'length' 2>/dev/null || echo "0")

if [ "$IDENTITY_COUNT" -eq 0 ]; then
    echo "No user-assigned identities found"
    exit 1
fi

echo "Found $IDENTITY_COUNT user-assigned identity/identities:"
echo ""
echo "$IDENTITIES" | jq -r 'to_entries[] | "\(.key) - Client ID: \(.value.clientId)"'
echo ""

echo "2. Getting identity client IDs..."
echo "================================="

# Extract all client IDs
CLIENT_IDS=$(echo "$IDENTITIES" | jq -r 'to_entries[] | .value.clientId' | head -1)
FIRST_CLIENT_ID=$(echo "$CLIENT_IDS" | head -1)

echo "Identities found:"
echo "$IDENTITIES" | jq -r 'to_entries[] | "\(.value.clientId) (Resource: \(.key))"'
echo ""

if [ "$IDENTITY_COUNT" -eq 1 ]; then
    SELECTED_CLIENT_ID="$FIRST_CLIENT_ID"
    echo "Using the single user-assigned identity: $SELECTED_CLIENT_ID"
else
    echo "Multiple identities found. Please select which one to use:"
    echo ""
    COUNT=1
    echo "$IDENTITIES" | jq -r 'to_entries[] | "\(.value.clientId)"' | while read CLIENT_ID; do
        echo "$COUNT) $CLIENT_ID"
        COUNT=$((COUNT + 1))
    done
    echo ""
    read -p "Enter number (1-$IDENTITY_COUNT) [default: 1]: " SELECTION
    SELECTION=${SELECTION:-1}
    
    SELECTED_CLIENT_ID=$(echo "$IDENTITIES" | jq -r "to_entries[] | .value.clientId" | sed -n "${SELECTION}p")
fi

echo ""
echo "Selected Client ID: $SELECTED_CLIENT_ID"
echo ""

echo "3. Updating SecretProviderClass..."
echo "==================================="

TENANT_ID=$(az account show --query tenantId -o tsv)

kubectl patch secretproviderclass authmanager-azure-keyvault -n muzika --type='json' -p="[
  {\"op\": \"replace\", \"path\": \"/spec/parameters/tenantId\", \"value\": \"$TENANT_ID\"},
  {\"op\": \"replace\", \"path\": \"/spec/parameters/userAssignedIdentityID\", \"value\": \"$SELECTED_CLIENT_ID\"},
  {\"op\": \"replace\", \"path\": \"/spec/parameters/keyvaultName\", \"value\": \"$KEYVAULT_NAME\"}
]"

echo "✓ SecretProviderClass updated with Client ID: $SELECTED_CLIENT_ID"
echo ""

echo "4. Granting Key Vault access..."
echo "==============================="

# Get the principal ID for this client ID
PRINCIPAL_ID=$(az ad sp show --id $SELECTED_CLIENT_ID --query id -o tsv 2>/dev/null || echo "")

if [ -z "$PRINCIPAL_ID" ]; then
    # Try alternative method - find by service principal display name
    PRINCIPAL_ID=$(az ad sp list --filter "servicePrincipalType eq 'ManagedIdentity'" --query "[?appId=='$SELECTED_CLIENT_ID'].id" -o tsv 2>/dev/null | head -1)
fi

if [ -z "$PRINCIPAL_ID" ]; then
    echo "⚠ Could not find principal ID for client ID: $SELECTED_CLIENT_ID"
    echo "Trying to grant access using client ID directly..."
    PRINCIPAL_ID="$SELECTED_CLIENT_ID"
fi

KEYVAULT_ID=$(az keyvault show --name $KEYVAULT_NAME --query "id" -o tsv 2>/dev/null || echo "")

if [ -z "$KEYVAULT_ID" ]; then
    echo "⚠ Could not find Key Vault: $KEYVAULT_NAME"
    echo "Grant access manually:"
    echo "  az role assignment create --role 'Key Vault Secrets User' --assignee $SELECTED_CLIENT_ID --scope <KEYVAULT_ID>"
else
    echo "Granting access to Key Vault: $KEYVAULT_NAME"
    az role assignment create \
        --role "Key Vault Secrets User" \
        --assignee "$PRINCIPAL_ID" \
        --scope "$KEYVAULT_ID" \
        --output none 2>/dev/null || echo "Access might already be granted or using client ID..."
    
    # Try with client ID if principal ID didn't work
    if ! az role assignment list --assignee "$PRINCIPAL_ID" --scope "$KEYVAULT_ID" &> /dev/null; then
        echo "Trying with client ID directly..."
        az role assignment create \
            --role "Key Vault Secrets User" \
            --assignee "$SELECTED_CLIENT_ID" \
            --scope "$KEYVAULT_ID" \
            --output none 2>/dev/null || echo "Note: You may need to grant access manually"
    fi
    
    echo "✓ Access granted (or already exists)"
fi

echo ""
echo "========================================="
echo "  Next Steps"
echo "========================================="
echo ""
echo "1. Verify SecretProviderClass:"
echo "   kubectl get secretproviderclass authmanager-azure-keyvault -n muzika -o yaml | grep -A 5 userAssignedIdentityID"
echo ""
echo "2. Restart pods:"
echo "   kubectl delete pods -n muzika -l app=authmanager"
echo ""
echo "3. Monitor pod status:"
echo "   kubectl get pods -n muzika -l app=authmanager -w"
echo ""

