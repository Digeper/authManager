#!/bin/bash
# Verify Key Vault secrets and force pod refresh

set -e

KEYVAULT_NAME="${1:-digeper}"

echo "========================================="
echo "  Verify and Refresh Secrets"
echo "========================================="
echo ""

echo "1. Checking Key Vault secrets..."
echo "================================="

# Check each secret
for SECRET_NAME in mysql-connection-string mysql-username mysql-password jwt-secret; do
    echo ""
    echo "Secret: $SECRET_NAME"
    VALUE=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $SECRET_NAME --query "value" -o tsv 2>/dev/null || echo "")
    
    if [ -z "$VALUE" ]; then
        echo "  ✗ Not found or empty"
    elif echo "$VALUE" | grep -q "REPLACE_WITH"; then
        echo "  ⚠ Still contains placeholder!"
        echo "  Value: $(echo $VALUE | cut -c1-80)..."
    else
        echo "  ✓ Has value"
        if [ "$SECRET_NAME" = "mysql-connection-string" ]; then
            echo "  Connection: $(echo $VALUE | sed 's/jdbc:mysql:\/\///' | cut -d'/' -f1)"
        elif [ "$SECRET_NAME" = "mysql-password" ] || [ "$SECRET_NAME" = "jwt-secret" ]; then
            echo "  Value: [hidden]"
        else
            echo "  Value: $VALUE"
        fi
    fi
done

echo ""
echo "2. Checking Kubernetes secret (synced from Key Vault)..."
echo "======================================================"

SYNCED_SECRET=$(kubectl get secret authmanager-secrets -n muzika -o jsonpath='{.data.MYSQL_URL}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

if [ -z "$SYNCED_SECRET" ]; then
    echo "⚠ Kubernetes secret not found or empty"
else
    echo "Current synced value: $SYNCED_SECRET"
    if echo "$SYNCED_SECRET" | grep -q "REPLACE_WITH"; then
        echo "⚠ Still has placeholder - secret needs to be refreshed"
    else
        echo "✓ Secret looks good"
    fi
fi

echo ""
echo "3. Force secret refresh..."
echo "=========================="
echo ""
echo "The Key Vault CSI driver should sync secrets automatically,"
echo "but sometimes pods need to be restarted to pick up changes."
echo ""

read -p "Restart pods to refresh secrets? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Deleting pods to force restart..."
    kubectl delete pods -n muzika -l app=authmanager
    
    echo ""
    echo "Waiting for pods to restart..."
    sleep 5
    
    echo "New pod status:"
    kubectl get pods -n muzika -l app=authmanager
    
    echo ""
    echo "Monitor logs:"
    echo "  kubectl logs -n muzika -l app=authmanager -f"
else
    echo "Skipped. Restart pods manually when ready:"
    echo "  kubectl delete pods -n muzika -l app=authmanager"
fi

echo ""
echo "4. If secrets still don't refresh..."
echo "===================================="
echo ""
echo "The Key Vault CSI driver syncs secrets periodically."
echo "If they don't update, you can:"
echo ""
echo "Option A: Delete and recreate SecretProviderClass"
echo "  kubectl delete secretproviderclass authmanager-azure-keyvault -n muzika"
echo "  kubectl apply -f AuthorizationManager/k8s/secret.yaml"
echo ""
echo "Option B: Manually sync by deleting the Kubernetes secret"
echo "  kubectl delete secret authmanager-secrets -n muzika"
echo "  # Wait a few seconds, then restart pods"
echo "  kubectl delete pods -n muzika -l app=authmanager"

