#!/bin/bash
# Check pod status and diagnose issues

set -e

POD_NAME=${1:-""}

if [ -z "$POD_NAME" ]; then
  echo "Getting pod name..."
  POD_NAME=$(kubectl get pods -n muzika -l app=authmanager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
fi

if [ -z "$POD_NAME" ]; then
  echo "❌ No authmanager pods found"
  exit 1
fi

echo "Checking pod: $POD_NAME"
echo ""

echo "=== Pod Status ==="
kubectl get pod "$POD_NAME" -n muzika -o wide
echo ""

echo "=== Pod Events ==="
kubectl describe pod "$POD_NAME" -n muzika | grep -A 20 "Events:" || echo "No events found"
echo ""

echo "=== Pod Conditions ==="
kubectl get pod "$POD_NAME" -n muzika -o jsonpath='{.status.conditions[*]}' | jq -r '.[] | "\(.type): \(.status) - \(.message)"' 2>/dev/null || kubectl get pod "$POD_NAME" -n muzika -o jsonpath='{.status.conditions[*].type}{"\n"}{.status.conditions[*].status}{"\n"}{.status.conditions[*].message}{"\n"}'
echo ""

echo "=== Container Status ==="
kubectl get pod "$POD_NAME" -n muzika -o jsonpath='{.status.containerStatuses[*]}' | jq -r '.[] | "\(.name): \(.state | to_entries[0].key) - \(.state | to_entries[0].value.reason // "N/A")"' 2>/dev/null || kubectl get pod "$POD_NAME" -n muzika -o jsonpath='{.status.containerStatuses[*].name}{"\n"}{.status.containerStatuses[*].state}{"\n"}'
echo ""

echo "=== Volume Mounts ==="
kubectl get pod "$POD_NAME" -n muzika -o jsonpath='{.spec.volumes[*].name}{"\n"}' | tr ' ' '\n' | grep -v "^$"
echo ""

echo "=== Key Vault CSI Driver Status ==="
kubectl get pods -n kube-system -l app=secrets-store-csi-driver 2>/dev/null || echo "CSI driver pods not found"
echo ""

echo "=== Recent Events (last 10) ==="
kubectl get events -n muzika --field-selector involvedObject.name=$POD_NAME --sort-by='.lastTimestamp' | tail -10

