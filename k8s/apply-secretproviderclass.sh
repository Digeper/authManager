#!/bin/bash
# Script to apply SecretProviderClass with actual values
# Usage: ./apply-secretproviderclass.sh <KEYVAULT_NAME> <TENANT_ID> [MANAGED_IDENTITY_CLIENT_ID]

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <KEYVAULT_NAME> <TENANT_ID> [MANAGED_IDENTITY_CLIENT_ID]"
    echo ""
    echo "Example:"
    echo "  $0 my-keyvault 12345678-1234-1234-1234-123456789012"
    echo ""
    echo "To get your values:"
    echo "  KEYVAULT_NAME: az keyvault list --query '[].name' -o table"
    echo "  TENANT_ID: az account show --query tenantId -o tsv"
    echo "  MANAGED_IDENTITY_CLIENT_ID: az identity list --query '[].{Name:name, ClientId:clientId}' -o table"
    exit 1
fi

KEYVAULT_NAME=$1
TENANT_ID=$2
MANAGED_IDENTITY_CLIENT_ID=${3:-""}

echo "Configuring SecretProviderClass with:"
echo "  Key Vault: $KEYVAULT_NAME"
echo "  Tenant ID: $TENANT_ID"
echo "  Managed Identity: ${MANAGED_IDENTITY_CLIENT_ID:-'(system-assigned)'}"
echo ""

# Create a temporary file with replaced values
TEMP_FILE=$(mktemp)
sed "s|\${KEYVAULT_NAME}|$KEYVAULT_NAME|g; s|\${TENANT_ID}|$TENANT_ID|g; s|\${MANAGED_IDENTITY_CLIENT_ID}|$MANAGED_IDENTITY_CLIENT_ID|g" \
    secretproviderclass.yaml > "$TEMP_FILE"

# Apply the SecretProviderClass
kubectl apply -f "$TEMP_FILE" -n muzika

# Clean up
rm "$TEMP_FILE"

echo ""
echo "SecretProviderClass applied successfully!"
echo ""
echo "Next steps:"
echo "1. Delete the manual secret: kubectl delete secret authmanager-secrets -n muzika"
echo "2. Restart the deployment: kubectl rollout restart deployment/authmanager -n muzika"
echo "3. Verify secret created: kubectl get secret authmanager-secrets -n muzika"
