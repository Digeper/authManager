#!/bin/bash
# Fix SecretProviderClass for system-assigned identity

set -e

echo "Fixing SecretProviderClass for system-assigned identity..."
echo ""

# Check current SecretProviderClass
if kubectl get secretproviderclass authmanager-azure-keyvault -n muzika &>/dev/null; then
  echo "Current SecretProviderClass configuration:"
  kubectl get secretproviderclass authmanager-azure-keyvault -n muzika -o yaml | grep -A 5 "userAssignedIdentityID" || echo "Not found in current config"
  echo ""
  
  # Delete existing SecretProviderClass
  echo "Deleting existing SecretProviderClass..."
  kubectl delete secretproviderclass authmanager-azure-keyvault -n muzika
  sleep 2
fi

# Update the file
SECRETPROVIDERCLASS_FILE="secretproviderclass.yaml"

if [ ! -f "$SECRETPROVIDERCLASS_FILE" ]; then
  echo "❌ SecretProviderClass file not found: $SECRETPROVIDERCLASS_FILE"
  exit 1
fi

# For system-assigned identity, set userAssignedIdentityID to empty string
echo "Updating SecretProviderClass to use system-assigned identity..."
sed -i.bak 's/userAssignedIdentityID: "[^"]*"/userAssignedIdentityID: ""/g' "$SECRETPROVIDERCLASS_FILE"
rm -f "${SECRETPROVIDERCLASS_FILE}.bak"

echo "✅ SecretProviderClass updated"
echo ""

# Apply the updated SecretProviderClass
echo "Applying updated SecretProviderClass..."
kubectl apply -f "$SECRETPROVIDERCLASS_FILE"

echo ""
echo "✅ SecretProviderClass applied. Restarting pods to pick up changes..."
kubectl rollout restart deployment/authmanager -n muzika

echo ""
echo "Waiting for pods to restart..."
sleep 5
kubectl get pods -n muzika -l app=authmanager -w

