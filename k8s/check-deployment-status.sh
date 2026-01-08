#!/bin/bash
# Check deployment status and diagnose issues

set -e

echo "=========================================="
echo "Deployment Status Check"
echo "=========================================="
echo ""

echo "=== Deployment Status ==="
kubectl get deployment authmanager -n muzika
echo ""

echo "=== ReplicaSet Status ==="
kubectl get rs -n muzika -l app=authmanager
echo ""

echo "=== Pod Status ==="
kubectl get pods -n muzika -l app=authmanager -o wide
echo ""

echo "=== Pod Details ==="
for pod in $(kubectl get pods -n muzika -l app=authmanager -o jsonpath='{.items[*].metadata.name}'); do
  echo ""
  echo "--- Pod: $pod ---"
  echo "Status:"
  kubectl get pod "$pod" -n muzika -o jsonpath='{.status.phase}{" - "}{.status.containerStatuses[0].state}{"\n"}' 2>/dev/null || echo "Unknown"
  
  echo "Container State:"
  kubectl get pod "$pod" -n muzika -o jsonpath='{.status.containerStatuses[0].state}' | jq '.' 2>/dev/null || kubectl get pod "$pod" -n muzika -o jsonpath='{.status.containerStatuses[0].state}'
  echo ""
  
  echo "Recent Events:"
  kubectl describe pod "$pod" -n muzika | grep -A 10 "Events:" | tail -5
  echo ""
done

echo "=== Key Vault CSI Driver Status ==="
kubectl get pods -n kube-system -l app=secrets-store-csi-driver
echo ""

echo "=== SecretProviderClass Status ==="
kubectl get secretproviderclass authmanager-azure-keyvault -n muzika -o yaml | grep -A 3 "userAssignedIdentityID" || echo "Not found"
echo ""

echo "=== Recent Events (last 20) ==="
kubectl get events -n muzika --sort-by='.lastTimestamp' | tail -20
echo ""

echo "=== Deployment Events ==="
kubectl describe deployment authmanager -n muzika | grep -A 10 "Events:" || echo "No events"
echo ""

