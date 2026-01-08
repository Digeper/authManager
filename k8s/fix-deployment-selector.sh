#!/bin/bash
# Quick fix for immutable Deployment selector error

set -e

echo "Fixing Deployment selector issue..."
echo ""

# Delete the existing Deployment
echo "Deleting existing Deployment..."
kubectl delete deployment authmanager -n muzika --ignore-not-found=true

echo "Waiting for Deployment to be fully deleted..."
kubectl wait --for=delete deployment/authmanager -n muzika --timeout=60s 2>/dev/null || true

sleep 3

echo "Reapplying manifests..."
kubectl apply -k .

echo ""
echo "✅ Deployment recreated. Waiting for rollout..."
kubectl rollout status deployment/authmanager -n muzika --timeout=300s

echo ""
echo "✅ Done! Check status with:"
echo "   kubectl get pods -n muzika -l app=authmanager"

