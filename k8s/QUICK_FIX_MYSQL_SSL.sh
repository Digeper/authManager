#!/bin/bash
# Quick fix: Update MySQL connection string in Key Vault with proper SSL parameters

set -e

echo "=========================================="
echo "Quick Fix: MySQL SSL Connection String"
echo "=========================================="
echo ""

# Get configuration
read -p "Enter Key Vault name: " KEYVAULT_NAME
read -p "Enter MySQL server hostname (e.g., digeper-mysql-server.mysql.database.azure.com): " MYSQL_HOST
read -p "Enter database name (e.g., userdb): " DB_NAME
read -p "Enter MySQL username: " MYSQL_USER
read -p "Enter MySQL password: " -s MYSQL_PASS
echo ""

# Build connection string with proper SSL parameters for Azure MySQL
CONN_STRING="jdbc:mysql://${MYSQL_HOST}:3306/${DB_NAME}?useSSL=true&requireSSL=true&verifyServerCertificate=false&serverTimezone=UTC&allowPublicKeyRetrieval=true&useUnicode=true&characterEncoding=UTF-8"

echo ""
echo "Updating Key Vault secrets..."
echo ""

# Update connection string
az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "mysql-connection-string" \
  --value "$CONN_STRING" \
  --output none

echo "✅ Connection string updated"

# Update username if different
CURRENT_USER=$(az keyvault secret show \
  --vault-name "$KEYVAULT_NAME" \
  --name "mysql-username" \
  --query "value" -o tsv 2>/dev/null || echo "")

if [ "$CURRENT_USER" != "$MYSQL_USER" ]; then
  az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "mysql-username" \
    --value "$MYSQL_USER" \
    --output none
  echo "✅ Username updated"
fi

# Update password
az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "mysql-password" \
  --value "$MYSQL_PASS" \
  --output none

echo "✅ Password updated"
echo ""

echo "=========================================="
echo "Refreshing Kubernetes secrets..."
echo "=========================================="
echo ""

# Delete the Kubernetes secret to force refresh
kubectl delete secret authmanager-secrets -n muzika --ignore-not-found=true

echo "✅ Kubernetes secret deleted"
echo ""

# Wait a moment for CSI driver to recreate it
echo "Waiting 5 seconds for CSI driver to recreate secret..."
sleep 5

# Restart pods to pick up new secrets
echo "Restarting pods..."
kubectl rollout restart deployment/authmanager -n muzika

echo ""
echo "✅ Pods restarted"
echo ""
echo "Monitor the deployment:"
echo "  kubectl get pods -n muzika -w"
echo ""
echo "Check logs:"
echo "  kubectl logs -f deployment/authmanager -n muzika"

