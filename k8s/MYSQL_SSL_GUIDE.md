# Azure MySQL SSL Configuration Guide

## Problem
Connection timeouts when connecting to Azure MySQL from AKS pods:
```
java.net.SocketTimeoutException: Connect timed out
Communications link failure
```

## Root Causes

### 1. Missing SSL Parameters in Connection String
Azure MySQL **requires SSL** for all connections. The connection string must include:
- `useSSL=true` - Enable SSL
- `requireSSL=true` - Require SSL (fail if not available)
- `verifyServerCertificate=false` - Don't verify cert (Azure uses self-signed certs)
- `serverTimezone=UTC` - Set timezone
- `allowPublicKeyRetrieval=true` - Allow public key retrieval

### 2. Firewall Rules
AKS nodes must be allowed to connect to MySQL:
- **Option A**: Allow Azure services (0.0.0.0-0.0.0.0) - Works for VNet integration
- **Option B**: Allow specific IP ranges from AKS subnet
- **Option C**: Use private endpoint with VNet peering

### 3. Network Connectivity
- VNet peering between AKS and MySQL (if using private endpoint)
- Network Security Groups (NSGs) allowing outbound MySQL traffic (port 3306)
- DNS resolution from AKS pods to MySQL hostname

## Quick Fix

### Step 1: Update Connection String in Key Vault

Run the quick fix script:
```bash
./AuthorizationManager/k8s/QUICK_FIX_MYSQL_SSL.sh
```

Or manually update the Key Vault secret:
```bash
# Get your values
KEYVAULT_NAME="your-keyvault-name"
MYSQL_HOST="digeper-mysql-server.mysql.database.azure.com"
DB_NAME="userdb"

# Build connection string with SSL
CONN_STRING="jdbc:mysql://${MYSQL_HOST}:3306/${DB_NAME}?useSSL=true&requireSSL=true&verifyServerCertificate=false&serverTimezone=UTC&allowPublicKeyRetrieval=true&useUnicode=true&characterEncoding=UTF-8"

# Update Key Vault
az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "mysql-connection-string" \
  --value "$CONN_STRING"
```

### Step 2: Configure Firewall Rules

#### Option A: Allow Azure Services (Recommended for VNet)
```bash
RESOURCE_GROUP="your-resource-group"
MYSQL_SERVER="digeper-mysql-server"

# For Flexible Server
az mysql flexible-server firewall-rule create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$MYSQL_SERVER" \
  --rule-name "AllowAzureServices" \
  --start-ip-address "0.0.0.0" \
  --end-ip-address "0.0.0.0"

# For Single Server
az mysql server firewall-rule create \
  --resource-group "$RESOURCE_GROUP" \
  --server-name "$MYSQL_SERVER" \
  --name "AllowAzureServices" \
  --start-ip-address "0.0.0.0" \
  --end-ip-address "0.0.0.0"
```

#### Option B: Allow AKS Subnet IP Range
```bash
# Get AKS subnet IP range
AKS_CLUSTER="your-aks-cluster"
AKS_RG="your-resource-group"

SUBNET_ID=$(az aks show \
  --name "$AKS_CLUSTER" \
  --resource-group "$AKS_RG" \
  --query "agentPoolProfiles[0].vnetSubnetId" -o tsv)

# Get subnet address prefix
SUBNET_PREFIX=$(az network vnet subnet show \
  --ids "$SUBNET_ID" \
  --query "addressPrefix" -o tsv)

# Calculate IP range (simplified - adjust based on your subnet)
START_IP=$(echo "$SUBNET_PREFIX" | cut -d'/' -f1)
# For /16 subnet, end IP is start + 255.255
# Adjust based on your actual subnet mask

az mysql flexible-server firewall-rule create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$MYSQL_SERVER" \
  --rule-name "AllowAKSSubnet" \
  --start-ip-address "$START_IP" \
  --end-ip-address "<calculated-end-ip>"
```

### Step 3: Refresh Kubernetes Secrets

After updating Key Vault, force Kubernetes to refresh:
```bash
# Delete the secret (CSI driver will recreate it)
kubectl delete secret authmanager-secrets -n muzika

# Wait a few seconds
sleep 5

# Restart pods to pick up new secrets
kubectl rollout restart deployment/authmanager -n muzika
```

### Step 4: Verify Connection

Monitor the pods:
```bash
# Watch pod status
kubectl get pods -n muzika -w

# Check logs
kubectl logs -f deployment/authmanager -n muzika
```

## Connection String Format

### Correct Format (with SSL)
```
jdbc:mysql://<hostname>:3306/<database>?useSSL=true&requireSSL=true&verifyServerCertificate=false&serverTimezone=UTC&allowPublicKeyRetrieval=true&useUnicode=true&characterEncoding=UTF-8
```

### Parameters Explained
- `useSSL=true` - **Required**: Enable SSL encryption
- `requireSSL=true` - **Required**: Fail if SSL is not available
- `verifyServerCertificate=false` - Don't verify server certificate (Azure uses self-signed certs)
- `serverTimezone=UTC` - Set timezone to avoid timezone issues
- `allowPublicKeyRetrieval=true` - Allow MySQL to send public key for authentication
- `useUnicode=true` - Use Unicode encoding
- `characterEncoding=UTF-8` - Set character encoding

## Application Configuration

The `application-k8s.properties` already includes SSL configuration via Hikari properties:
```properties
spring.datasource.hikari.data-source-properties.useSSL=true
spring.datasource.hikari.data-source-properties.requireSSL=true
spring.datasource.hikari.data-source-properties.verifyServerCertificate=false
```

**Note**: Connection string parameters take precedence over Hikari properties, so it's best to include SSL parameters in the connection string itself.

## Troubleshooting

### 1. Still Getting Timeout After SSL Fix

Check network connectivity:
```bash
# Test DNS resolution from a pod
kubectl run -it --rm debug --image=busybox --restart=Never -n muzika -- nslookup digeper-mysql-server.mysql.database.azure.com

# Test TCP connection (if telnet/netcat available)
kubectl run -it --rm debug --image=busybox --restart=Never -n muzika -- nc -zv digeper-mysql-server.mysql.database.azure.com 3306
```

### 2. VNet Integration Issues

If MySQL uses a private endpoint:
- Verify VNet peering between AKS VNet and MySQL VNet
- Check NSG rules allowing outbound traffic on port 3306
- Verify DNS resolution (may need private DNS zone)

### 3. Firewall Rules Not Working

- Check if MySQL is using public access or private endpoint
- Verify firewall rule was created: `az mysql flexible-server firewall-rule list --resource-group <rg> --name <server>`
- Try temporarily allowing all IPs (0.0.0.0-255.255.255.255) for testing

### 4. SSL Handshake Errors

If you see SSL handshake errors:
- Ensure `verifyServerCertificate=false` is in the connection string
- Check MySQL server SSL enforcement settings in Azure Portal
- Verify the connection string is correctly formatted (no extra spaces, proper encoding)

## Verification Checklist

- [ ] Connection string in Key Vault has all SSL parameters
- [ ] Firewall rules allow AKS nodes to connect
- [ ] Kubernetes secret was deleted and recreated
- [ ] Pods were restarted after secret update
- [ ] Network connectivity is verified (DNS, TCP)
- [ ] VNet peering is configured (if using private endpoint)
- [ ] NSG rules allow outbound MySQL traffic

## Additional Resources

- [Azure MySQL SSL Configuration](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/how-to-connect-tls-ssl)
- [AKS Network Configuration](https://learn.microsoft.com/en-us/azure/aks/configure-azure-cni)
- [Azure MySQL Firewall Rules](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/concepts-networking)

