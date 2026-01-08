#!/bin/bash
# Check if Key Vault secrets are syncing to Kubernetes

echo "========================================="
echo "  Check Secret Sync Status"
echo "========================================="
echo ""

echo "1. Checking if Kubernetes secret exists..."
echo "==========================================="
SECRET_EXISTS=$(kubectl get secret authmanager-secrets -n muzika 2>/dev/null && echo "yes" || echo "no")
echo "Secret exists: $SECRET_EXISTS"

if [ "$SECRET_EXISTS" = "yes" ]; then
    echo ""
    echo "Secret details:"
    kubectl get secret authmanager-secrets -n muzika -o yaml | grep -A 5 "data:"
    
    echo ""
    echo "Decoded MYSQL_URL (first 80 chars):"
    kubectl get secret authmanager-secrets -n muzika -o jsonpath='{.data.MYSQL_URL}' | base64 -d 2>/dev/null | cut -c1-80 || echo "Could not decode"
else
    echo ""
    echo "⚠ Secret does not exist!"
fi

echo ""
echo "2. Checking SecretProviderClass..."
echo "==================================="
SPC_EXISTS=$(kubectl get secretproviderclass authmanager-azure-keyvault -n muzika 2>/dev/null && echo "yes" || echo "no")
echo "SecretProviderClass exists: $SPC_EXISTS"

if [ "$SPC_EXISTS" = "yes" ]; then
    echo ""
    echo "SecretProviderClass status:"
    kubectl get secretproviderclass authmanager-azure-keyvault -n muzika -o yaml | grep -A 10 "spec:" | head -15
else
    echo ""
    echo "⚠ SecretProviderClass does not exist!"
    echo "Apply it with: kubectl apply -f AuthorizationManager/k8s/secret.yaml"
fi

echo ""
echo "3. Checking CSI driver pods..."
echo "==============================="
CSI_PODS=$(kubectl get pods -n kube-system -l app=secrets-store-csi-driver --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "CSI driver pods: $CSI_PODS"

if [ "$CSI_PODS" -gt 0 ]; then
    echo "CSI driver pods status:"
    kubectl get pods -n kube-system -l app=secrets-store-csi-driver
else
    echo "⚠ No CSI driver pods found!"
fi

echo ""
echo "4. Checking pod events for secret mount errors..."
echo "=================================================="
kubectl get events -n muzika --field-selector involvedObject.kind=Pod --sort-by='.lastTimestamp' | grep -i "secret\|mount" | tail -5

echo ""
echo "========================================="
echo "  Fix Options"
echo "========================================="
echo ""

if [ "$SECRET_EXISTS" = "no" ]; then
    echo "Secret is missing. Options:"
    echo ""
    echo "Option 1: Wait for CSI driver to sync (can take 1-2 minutes)"
    echo "  Watch for secret: kubectl get secret authmanager-secrets -n muzika -w"
    echo ""
    echo "Option 2: Manually create secret from Key Vault values"
    echo "  Run: ./AuthorizationManager/k8s/CREATE_MANUAL_SECRET.sh"
    echo ""
    echo "Option 3: Check if SecretProviderClass is correct"
    echo "  kubectl describe secretproviderclass authmanager-azure-keyvault -n muzika"
else
    echo "Secret exists. If pods still can't find it:"
    echo "  1. Restart pods: kubectl delete pods -n muzika -l app=authmanager"
    echo "  2. Check deployment references: kubectl get deployment authmanager -n muzika -o yaml | grep -A 5 secretRef"
fi

