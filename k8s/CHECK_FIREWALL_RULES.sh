#!/bin/bash
# Check and configure MySQL firewall rules

set -e

read -p "Enter Azure Resource Group name: " RESOURCE_GROUP
read -p "Enter MySQL server name (e.g., digeper-mysql-server): " MYSQL_SERVER

echo ""
echo "=========================================="
echo "Checking current firewall rules..."
echo "=========================================="
echo ""

# Try Flexible Server first
az mysql flexible-server firewall-rule list \
  --resource-group "$RESOURCE_GROUP" \
  --name "$MYSQL_SERVER" \
  --output table 2>/dev/null || \
# Fall back to Single Server
az mysql server firewall-rule list \
  --resource-group "$RESOURCE_GROUP" \
  --server-name "$MYSQL_SERVER" \
  --output table 2>/dev/null || \
echo "⚠️  Could not list firewall rules"

echo ""
echo "=========================================="
echo "Adding firewall rule to allow Azure services..."
echo "=========================================="
echo ""

read -p "Add rule to allow Azure services (0.0.0.0-0.0.0.0)? (y/n): " CONFIRM

if [ "$CONFIRM" = "y" ]; then
  # Try Flexible Server first
  az mysql flexible-server firewall-rule create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$MYSQL_SERVER" \
    --rule-name "AllowAzureServices" \
    --start-ip-address "0.0.0.0" \
    --end-ip-address "0.0.0.0" \
    --output none 2>/dev/null || \
  # Fall back to Single Server
  az mysql server firewall-rule create \
    --resource-group "$RESOURCE_GROUP" \
    --server-name "$MYSQL_SERVER" \
    --name "AllowAzureServices" \
    --start-ip-address "0.0.0.0" \
    --end-ip-address "0.0.0.0" \
    --output none 2>/dev/null || \
  echo "⚠️  Could not add firewall rule"
  
  if [ $? -eq 0 ]; then
    echo "✅ Firewall rule added: AllowAzureServices (0.0.0.0-0.0.0.0)"
  fi
fi

echo ""
echo "=========================================="
echo "Verifying firewall rules..."
echo "=========================================="
echo ""

az mysql flexible-server firewall-rule list \
  --resource-group "$RESOURCE_GROUP" \
  --name "$MYSQL_SERVER" \
  --output table 2>/dev/null || \
az mysql server firewall-rule list \
  --resource-group "$RESOURCE_GROUP" \
  --server-name "$MYSQL_SERVER" \
  --output table 2>/dev/null || \
echo "⚠️  Could not list firewall rules"

