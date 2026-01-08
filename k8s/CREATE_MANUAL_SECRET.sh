#!/bin/bash
# Create Kubernetes secret manually from Key Vault values (temporary workaround)

set -e

KEYVAULT_NAME="${1:-digeper}"

echo "========================================="
echo "  Create Manual Secret from Key Vault"
echo "========================================="
echo ""

# Check if logged in
if ! az account show &> /dev/null; then
    echo "ERROR: Please login to Azure first: az login"
    exit 1
fi

echo "Fetching secrets from Key Vault: $KEYVAULT_NAME"
echo ""

# Get secrets from Key Vault
MYSQL_URL=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name mysql-connection-string --query "value" -o tsv 2>/dev/null || echo "")
MYSQL_USERNAME=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name mysql-username --query "value" -o tsv 2>/dev/null || echo "")
MYSQL_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name mysql-password --query "value" -o tsv 2>/dev/null || echo "")
JWT_SECRET=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name jwt-secret --query "value" -o tsv 2>/dev/null || echo "")

if [ -z "$MYSQL_URL" ] || [ -z "$MYSQL_USERNAME" ] || [ -z "$MYSQL_PASSWORD" ] || [ -z "$JWT_SECRET" ]; then
    echo "ERROR: One or more secrets are missing from Key Vault"
    echo ""
    echo "Found:"
    echo "  MYSQL_URL: $([ -n "$MYSQL_URL" ] && echo "✓" || echo "✗")"
    echo "  MYSQL_USERNAME: $([ -n "$MYSQL_USERNAME" ] && echo "✓" || echo "✗")"
    echo "  MYSQL_PASSWORD: $([ -n "$MYSQL_PASSWORD" ] && echo "✓" || echo "✗")"
    echo "  JWT_SECRET: $([ -n "$JWT_SECRET" ] && echo "✓" || echo "✗")"
    exit 1
fi

echo "✓ All secrets found in Key Vault"
echo ""

echo "Creating Kubernetes secret..."
kubectl create secret generic authmanager-secrets \
    --namespace=muzika \
    --from-literal=MYSQL_URL="$MYSQL_URL" \
    --from-literal=MYSQL_USERNAME="$MYSQL_USERNAME" \
    --from-literal=MYSQL_PASSWORD="$MYSQL_PASSWORD" \
    --from-literal=JWT_SECRET="$JWT_SECRET" \
    --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✓ Secret created!"
echo ""

echo "Verifying secret:"
kubectl get secret authmanager-secrets -n muzika

echo ""
echo "Next: Restart pods"
echo "  kubectl delete pods -n muzika -l app=authmanager"

