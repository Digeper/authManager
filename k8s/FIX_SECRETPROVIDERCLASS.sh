#!/bin/bash
# Fix SecretProviderClass by replacing placeholders with actual values

set -e

RESOURCE_GROUP="${RESOURCE_GROUP:-Digeper}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-Digeper-aks}"

# Key Vault name - get from SecretProviderClass if not provided
if [ -z "$KEYVAULT_NAME" ]; then
    KEYVAULT_NAME=$(kubectl get secretproviderclass authmanager-azure-keyvault -n muzika -o jsonpath='{.spec.parameters.keyvaultName}' 2>/dev/null || echo "")
    if [ -z "$KEYVAULT_NAME" ] || [ "$KEYVAULT_NAME" = "\${KEYVAULT_NAME}" ]; then
        echo "ERROR: KEYVAULT_NAME not set and not found in SecretProviderClass"
        echo ""
        echo "Usage: $0 [KEYVAULT_NAME]"
        echo "Or set: KEYVAULT_NAME=<your-keyvault-name> $0"
        echo ""
        echo "To find your Key Vault:"
        echo "  az keyvault list --query '[].{name:name,resourceGroup:resourceGroup}' -o table"
        exit 1
    fi
fi

echo "========================================="
echo "  Fix SecretProviderClass Placeholders"
echo "========================================="
echo ""

# Check if logged in
if ! az account show &> /dev/null; then
    echo "ERROR: Please login to Azure first: az login"
    exit 1
fi

echo "1. Getting Azure Tenant ID..."
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Tenant ID: $TENANT_ID"
echo ""

echo "2. Getting Managed Identity Client ID..."
# Try to get from AKS cluster
IDENTITY_TYPE=$(az aks show \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --query "identity.type" -o tsv)

if [ "$IDENTITY_TYPE" = "UserAssigned" ]; then
    # User-assigned identity
    IDENTITY_ID=$(az aks show \
        --resource-group $RESOURCE_GROUP \
        --cluster-name $AKS_CLUSTER_NAME \
        --query "identity.userAssignedIdentities" -o json | jq -r 'keys[0]' 2>/dev/null || echo "")
    
    if [ -n "$IDENTITY_ID" ] && [ "$IDENTITY_ID" != "null" ]; then
        # Extract resource group and name from identity ID
        IDENTITY_RG=$(echo "$IDENTITY_ID" | sed 's|.*/resourceGroups/\([^/]*\).*|\1|')
        IDENTITY_NAME=$(echo "$IDENTITY_ID" | sed 's|.*/providers/Microsoft.ManagedIdentity/userAssignedIdentities/\([^/]*\).*|\1|')
        
        MANAGED_IDENTITY_CLIENT_ID=$(az identity show \
            --resource-group $IDENTITY_RG \
            --name $IDENTITY_NAME \
            --query clientId -o tsv 2>/dev/null || echo "")
    fi
elif [ "$IDENTITY_TYPE" = "SystemAssigned" ]; then
    # System-assigned identity - use empty string
    MANAGED_IDENTITY_CLIENT_ID=""
    echo "Using system-assigned identity (empty userAssignedIdentityID)"
else
    # Try to get principal ID and convert (not perfect, but better than placeholder)
    PRINCIPAL_ID=$(az aks show \
        --resource-group $RESOURCE_GROUP \
        --cluster-name $AKS_CLUSTER_NAME \
        --query "identity.principalId" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$PRINCIPAL_ID" ]; then
        echo "For system-assigned identity, leave userAssignedIdentityID empty"
        MANAGED_IDENTITY_CLIENT_ID=""
    else
        echo "⚠ Could not determine managed identity"
        read -p "Enter Managed Identity Client ID (or press Enter for system-assigned/empty): " MANAGED_IDENTITY_CLIENT_ID
        MANAGED_IDENTITY_CLIENT_ID=${MANAGED_IDENTITY_CLIENT_ID:-""}
    fi
fi

echo "Managed Identity Client ID: ${MANAGED_IDENTITY_CLIENT_ID:-'(empty for system-assigned)'}"
echo ""

echo "3. Updating SecretProviderClass..."
echo "=================================="

# Export SecretProviderClass
kubectl get secretproviderclass authmanager-azure-keyvault -n muzika -o yaml > /tmp/spc-backup.yaml 2>/dev/null || {
    echo "ERROR: SecretProviderClass not found. Make sure it's deployed."
    exit 1
}

echo "Backup saved to: /tmp/spc-backup.yaml"
echo ""

# Create updated version
cat > /tmp/spc-updated.yaml <<EOF
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: authmanager-azure-keyvault
  namespace: muzika
  labels:
    app: authmanager
    app.kubernetes.io/name: authmanager
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "${MANAGED_IDENTITY_CLIENT_ID}"
    keyvaultName: "${KEYVAULT_NAME}"
    tenantId: "${TENANT_ID}"
    objects: |
      array:
        - |
          objectName: mysql-connection-string
          objectType: secret
          objectAlias: MYSQL_URL
        - |
          objectName: mysql-username
          objectType: secret
          objectAlias: MYSQL_USERNAME
        - |
          objectName: mysql-password
          objectType: secret
          objectAlias: MYSQL_PASSWORD
        - |
          objectName: jwt-secret
          objectType: secret
          objectAlias: JWT_SECRET
  secretObjects:
    - secretName: authmanager-secrets
      type: Opaque
      data:
        - objectName: MYSQL_URL
          key: MYSQL_URL
        - objectName: MYSQL_USERNAME
          key: MYSQL_USERNAME
        - objectName: MYSQL_PASSWORD
          key: MYSQL_PASSWORD
        - objectName: JWT_SECRET
          key: JWT_SECRET
EOF

echo "Updated SecretProviderClass:"
echo "----------------------------"
cat /tmp/spc-updated.yaml
echo ""

read -p "Apply this update? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl apply -f /tmp/spc-updated.yaml
    
    echo ""
    echo "✓ SecretProviderClass updated!"
    echo ""
    echo "4. Next steps:"
    echo "============="
    echo ""
    echo "Grant Key Vault access (if not already done):"
    echo "  PRINCIPAL_ID=\$(az aks show --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query 'identity.principalId' -o tsv)"
    echo "  KEYVAULT_ID=\$(az keyvault show --name $KEYVAULT_NAME --query 'id' -o tsv)"
    echo "  az role assignment create --role 'Key Vault Secrets User' --assignee \$PRINCIPAL_ID --scope \$KEYVAULT_ID"
    echo ""
    echo "Restart pods:"
    echo "  kubectl delete pods -n muzika -l app=authmanager"
else
    echo "Cancelled. File saved to /tmp/spc-updated.yaml"
fi

