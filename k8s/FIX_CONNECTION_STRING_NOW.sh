#!/bin/bash
# Fix MySQL connection string - RUN THIS MANUALLY

set -e

KEYVAULT_NAME="digeper"
MYSQL_HOST="digeper-mysql-server.mysql.database.azure.com"
DB_NAME="userdb"

# Build connection string with proper SSL parameters
CONN_STRING="jdbc:mysql://${MYSQL_HOST}:3306/${DB_NAME}?useSSL=true&requireSSL=true&verifyServerCertificate=false&serverTimezone=UTC&allowPublicKeyRetrieval=true&useUnicode=true&characterEncoding=UTF-8"

echo "=========================================="
echo "Updating Key Vault connection string..."
echo "=========================================="
echo ""

az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "mysql-connection-string" \
  --value "$CONN_STRING"

echo ""
echo "✅ Connection string updated!"
echo ""
echo "New connection string:"
echo "$CONN_STRING" | sed 's/:[^:@]*@/:***@/g'
echo ""

echo "=========================================="
echo "Refreshing Kubernetes secret..."
echo "=========================================="
echo ""

# Delete the secret to force CSI driver to recreate it
kubectl delete secret authmanager-secrets -n muzika --ignore-not-found=true

echo "✅ Secret deleted"
echo "Waiting 5 seconds for CSI driver to recreate..."
sleep 5

# Restart pods
echo "Restarting pods..."
kubectl rollout restart deployment/authmanager -n muzika

echo ""
echo "✅ Done! Monitor with:"
echo "   kubectl get pods -n muzika -w"
echo "   kubectl logs -f deployment/authmanager -n muzika"
echo ""

