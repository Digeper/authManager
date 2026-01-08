#!/bin/bash
# Quick fix script to diagnose and fix pod scheduling issues

echo "=== Cluster Diagnostics ==="
echo ""
echo "1. Node Status:"
kubectl get nodes -o wide

echo ""
echo "2. Node Resources:"
kubectl describe nodes | grep -A 5 "Allocated resources" || echo "Could not get resource info"

echo ""
echo "3. Pending Pods:"
kubectl get pods --all-namespaces --field-selector=status.phase=Pending

echo ""
echo "4. AuthManager Pod Events:"
kubectl describe pods -n muzika -l app=authmanager 2>/dev/null | grep -A 20 "Events:" || echo "No authmanager pods found"

echo ""
echo "5. Key Vault CSI Driver Status:"
kubectl describe pods -n kube-system -l app=secrets-store-csi-driver 2>/dev/null | grep -A 20 "Events:" || echo "CSI driver pod not found"

echo ""
echo "=== Suggested Fixes ==="
echo ""
echo "If nodes show insufficient resources:"
echo "  az aks nodepool scale --resource-group <RG> --cluster-name <AKS> --name nodepool1 --node-count 3"
echo ""
echo "If Key Vault CSI driver is stuck:"
echo "  1. Re-enable: az aks enable-addons --resource-group <RG> --name <AKS> --addons azure-keyvault-secrets-provider"
echo "  2. Or use manual secrets instead (see TROUBLESHOOTING.md)"
echo ""
echo "To temporarily bypass Key Vault:"
echo "  1. Create manual secret: kubectl create secret generic authmanager-secrets -n muzika --from-literal=..."
echo "  2. Use deployment-no-keyvault.yaml"
