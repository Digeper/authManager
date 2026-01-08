#!/bin/bash
# Quick fix: Check and grant managed identity access or disable Key Vault temporarily

set -e

RESOURCE_GROUP="${RESOURCE_GROUP:-Digeper}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-Digeper-aks}"

echo "========================================="
echo "  Quick Fix: Managed Identity Issue"
echo "========================================="
echo ""

# Check if logged in
if ! az account show &> /dev/null; then
    echo "ERROR: Please login to Azure first: az login"
    exit 1
fi

echo "1. Checking AKS managed identity..."
PRINCIPAL_ID=$(az aks show \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --query "identity.principalId" -o tsv 2>/dev/null || echo "")

if [ -z "$PRINCIPAL_ID" ] || [ "$PRINCIPAL_ID" = "None" ]; then
    echo "✗ No managed identity found on AKS cluster"
    echo ""
    echo "Your cluster needs managed identity enabled."
    echo "Enable it with:"
    echo "  az aks update --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --enable-managed-identity"
    echo ""
    exit 1
fi

echo "✓ Found managed identity: $PRINCIPAL_ID"
echo ""

echo "2. Checking SecretProviderClass configuration..."
SECRET_PROVIDER=$(kubectl get secretproviderclass authmanager-azure-keyvault -n muzika -o yaml 2>/dev/null || echo "")

if [ -z "$SECRET_PROVIDER" ]; then
    echo "⚠ SecretProviderClass not found"
    exit 1
fi

USER_ASSIGNED_ID=$(echo "$SECRET_PROVIDER" | grep -A 1 "userAssignedIdentityID:" | tail -1 | awk '{print $2}' | tr -d '"' || echo "")
KEYVAULT_NAME=$(echo "$SECRET_PROVIDER" | grep -A 1 "keyvaultName:" | tail -1 | awk '{print $2}' | tr -d '"' || echo "")

echo "Key Vault: $KEYVAULT_NAME"
echo "Configured Identity ID: $USER_ASSIGNED_ID"
echo ""

echo "3. Options to fix:"
echo "=================="
echo ""
echo "Option A: Grant Key Vault access (if you have Key Vault set up)"
echo "Option B: Temporarily disable Key Vault and use manual secrets"
echo ""

read -p "Choose option (A/B) [default: B]: " CHOICE
CHOICE=${CHOICE:-B}

case $CHOICE in
    A|a)
        if [ -z "$KEYVAULT_NAME" ] || [ "$KEYVAULT_NAME" = "\${KEYVAULT_NAME}" ]; then
            echo ""
            echo "ERROR: Key Vault name not configured in SecretProviderClass"
            exit 1
        fi
        
        echo ""
        echo "Granting Key Vault access..."
        KEYVAULT_ID=$(az keyvault show \
            --name $KEYVAULT_NAME \
            --query "id" -o tsv 2>/dev/null || echo "")
        
        if [ -z "$KEYVAULT_ID" ]; then
            echo "ERROR: Key Vault '$KEYVAULT_NAME' not found"
            exit 1
        fi
        
        # Grant access
        az role assignment create \
            --role "Key Vault Secrets User" \
            --assignee $PRINCIPAL_ID \
            --scope $KEYVAULT_ID \
            --output none 2>/dev/null || echo "Access might already be granted"
        
        echo "✓ Access granted (or already exists)"
        echo ""
        echo "Next: Restart pods"
        echo "  kubectl delete pods -n muzika -l app=authmanager"
        ;;
    B|b)
        echo ""
        echo "Temporarily disabling Key Vault..."
        echo ""
        echo "Step 1: Creating manual secrets..."
        echo ""
        echo "You'll need to provide:"
        read -p "MySQL URL: " MYSQL_URL
        read -p "MySQL Username: " MYSQL_USER
        read -sp "MySQL Password: " MYSQL_PASS
        echo ""
        read -sp "JWT Secret: " JWT_SECRET
        echo ""
        
        # Create secret
        kubectl create secret generic authmanager-secrets -n muzika \
            --from-literal=MYSQL_URL="$MYSQL_URL" \
            --from-literal=MYSQL_USERNAME="$MYSQL_USER" \
            --from-literal=MYSQL_PASSWORD="$MYSQL_PASS" \
            --from-literal=JWT_SECRET="$JWT_SECRET" \
            --dry-run=client -o yaml | kubectl apply -f -
        
        echo ""
        echo "✓ Manual secrets created"
        echo ""
        echo "Step 2: Commenting out Key Vault volume mount in deployment..."
        echo ""
        echo "Edit AuthorizationManager/k8s/deployment.yaml:"
        echo "  Comment out the 'volumes:' section (around line 95-101)"
        echo "  Comment out the 'volumeMounts:' section (around line 57-60)"
        echo ""
        echo "Or apply a deployment without Key Vault:"
        echo "  kubectl apply -f AuthorizationManager/k8s/deployment-no-keyvault.yaml"
        echo ""
        echo "Then restart pods:"
        echo "  kubectl delete pods -n muzika -l app=authmanager"
        ;;
esac

