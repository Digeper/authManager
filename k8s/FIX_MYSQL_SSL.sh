#!/bin/bash
# Fix MySQL SSL Configuration and Firewall Rules for Azure MySQL

set -e

echo "=========================================="
echo "Azure MySQL SSL & Network Configuration Fix"
echo "=========================================="
echo ""

# Get Azure configuration
read -p "Enter Azure Resource Group name: " RESOURCE_GROUP
read -p "Enter Azure MySQL server name (e.g., digeper-mysql-server): " MYSQL_SERVER
read -p "Enter Key Vault name: " KEYVAULT_NAME
read -p "Enter database name (e.g., userdb): " DB_NAME

echo ""
echo "Step 1: Checking current Key Vault connection string..."
echo ""

# Get current connection string
CURRENT_CONN=$(az keyvault secret show \
  --vault-name "$KEYVAULT_NAME" \
  --name "mysql-connection-string" \
  --query "value" -o tsv 2>/dev/null || echo "")

if [ -z "$CURRENT_CONN" ]; then
  echo "❌ Connection string not found in Key Vault!"
  exit 1
fi

echo "Current connection string:"
echo "$CURRENT_CONN" | sed 's/:[^:@]*@/:***@/g'
echo ""

# Extract hostname from connection string
HOSTNAME=$(echo "$CURRENT_CONN" | sed -n 's/.*:\/\/\([^:]*\):.*/\1/p')
if [ -z "$HOSTNAME" ]; then
  HOSTNAME="${MYSQL_SERVER}.mysql.database.azure.com"
fi

echo "MySQL Hostname: $HOSTNAME"
echo ""

# Build proper SSL connection string
echo "Step 2: Building proper SSL connection string..."
echo ""

# Azure MySQL requires SSL with these parameters:
# - useSSL=true: Enable SSL
# - requireSSL=true: Require SSL (fail if SSL not available)
# - verifyServerCertificate=false: Don't verify server cert (Azure uses self-signed certs)
# - serverTimezone=UTC: Set timezone
# - allowPublicKeyRetrieval=true: Allow public key retrieval for authentication

NEW_CONN="jdbc:mysql://${HOSTNAME}:3306/${DB_NAME}?useSSL=true&requireSSL=true&verifyServerCertificate=false&serverTimezone=UTC&allowPublicKeyRetrieval=true&useUnicode=true&characterEncoding=UTF-8"

echo "New connection string (with SSL):"
echo "$NEW_CONN" | sed 's/:[^:@]*@/:***@/g'
echo ""

read -p "Update connection string in Key Vault? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
  echo "Skipping connection string update."
else
  echo ""
  echo "Updating Key Vault secret..."
  az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "mysql-connection-string" \
    --value "$NEW_CONN" \
    --output none
  
  echo "✅ Connection string updated in Key Vault!"
fi

echo ""
echo "Step 3: Checking MySQL firewall rules..."
echo ""

# Get AKS cluster info
read -p "Enter AKS cluster name: " AKS_CLUSTER
AKS_RG=$(az aks show --name "$AKS_CLUSTER" --resource-group "$RESOURCE_GROUP" --query "nodeResourceGroup" -o tsv 2>/dev/null || echo "")

if [ -z "$AKS_RG" ]; then
  echo "⚠️  Could not determine AKS node resource group. Please check firewall rules manually."
else
  echo "AKS Node Resource Group: $AKS_RG"
  echo ""
  
  # Get outbound IPs from AKS nodes
  echo "Getting AKS node outbound IPs..."
  NODE_IPS=$(az vmss list \
    --resource-group "$AKS_RG" \
    --query "[].publicIpAddresses[].ipAddress" -o tsv 2>/dev/null || echo "")
  
  if [ -z "$NODE_IPS" ]; then
    echo "⚠️  Could not get node IPs. Checking firewall rules..."
  else
    echo "Found node IPs:"
    echo "$NODE_IPS"
    echo ""
  fi
fi

# List current firewall rules
echo "Current MySQL firewall rules:"
az mysql flexible-server firewall-rule list \
  --resource-group "$RESOURCE_GROUP" \
  --name "$MYSQL_SERVER" \
  --output table 2>/dev/null || \
az mysql server firewall-rule list \
  --resource-group "$RESOURCE_GROUP" \
  --server-name "$MYSQL_SERVER" \
  --output table 2>/dev/null || \
echo "⚠️  Could not list firewall rules. Please check manually."

echo ""
echo "Step 4: Adding firewall rule for AKS..."
echo ""

# Option 1: Allow Azure services
echo "Option 1: Allow Azure services (recommended for VNet integration)"
read -p "Add rule to allow Azure services? (y/n): " ALLOW_AZURE
if [ "$ALLOW_AZURE" = "y" ]; then
  # Try flexible server first
  az mysql flexible-server firewall-rule create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$MYSQL_SERVER" \
    --rule-name "AllowAzureServices" \
    --start-ip-address "0.0.0.0" \
    --end-ip-address "0.0.0.0" \
    --output none 2>/dev/null || \
  az mysql server firewall-rule create \
    --resource-group "$RESOURCE_GROUP" \
    --server-name "$MYSQL_SERVER" \
    --name "AllowAzureServices" \
    --start-ip-address "0.0.0.0" \
    --end-ip-address "0.0.0.0" \
    --output none 2>/dev/null || \
  echo "⚠️  Could not add firewall rule. Please add manually in Azure Portal."
  
  if [ $? -eq 0 ]; then
    echo "✅ Firewall rule added: AllowAzureServices (0.0.0.0-0.0.0.0)"
  fi
fi

# Option 2: Allow specific IP range
echo ""
echo "Option 2: Allow specific IP range"
read -p "Add rule for specific IP range? (y/n): " ALLOW_IP
if [ "$ALLOW_IP" = "y" ]; then
  read -p "Enter start IP (e.g., 10.224.0.0): " START_IP
  read -p "Enter end IP (e.g., 10.224.255.255): " END_IP
  read -p "Enter rule name: " RULE_NAME
  
  az mysql flexible-server firewall-rule create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$MYSQL_SERVER" \
    --rule-name "$RULE_NAME" \
    --start-ip-address "$START_IP" \
    --end-ip-address "$END_IP" \
    --output none 2>/dev/null || \
  az mysql server firewall-rule create \
    --resource-group "$RESOURCE_GROUP" \
    --server-name "$MYSQL_SERVER" \
    --name "$RULE_NAME" \
    --start-ip-address "$START_IP" \
    --end-ip-address "$END_IP" \
    --output none 2>/dev/null || \
  echo "⚠️  Could not add firewall rule."
  
  if [ $? -eq 0 ]; then
    echo "✅ Firewall rule added: $RULE_NAME ($START_IP-$END_IP)"
  fi
fi

echo ""
echo "Step 5: Checking VNet integration (if applicable)..."
echo ""

# Check if MySQL is in a VNet
VNET_CONFIG=$(az mysql flexible-server show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$MYSQL_SERVER" \
  --query "network.publicNetworkAccess" -o tsv 2>/dev/null || echo "unknown")

if [ "$VNET_CONFIG" = "Disabled" ]; then
  echo "✅ MySQL is using VNet integration (private endpoint)"
  echo "   Make sure AKS can reach the MySQL private endpoint via VNet peering or VPN."
else
  echo "ℹ️  MySQL is using public access. Firewall rules are required."
fi

echo ""
echo "=========================================="
echo "Next Steps:"
echo "=========================================="
echo ""
echo "1. If you updated the connection string, delete the Kubernetes secret to force refresh:"
echo "   kubectl delete secret authmanager-secrets -n muzika"
echo ""
echo "2. Restart the pods to pick up the new connection string:"
echo "   kubectl rollout restart deployment/authmanager -n muzika"
echo ""
echo "3. Monitor the pods:"
echo "   kubectl logs -f deployment/authmanager -n muzika"
echo ""
echo "4. If still timing out, check:"
echo "   - VNet peering between AKS and MySQL (if using private endpoint)"
echo "   - Network security groups (NSGs) allowing outbound MySQL traffic"
echo "   - DNS resolution from AKS pods to MySQL hostname"
echo ""

