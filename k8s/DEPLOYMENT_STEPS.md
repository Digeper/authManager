# AuthorizationManager Deployment Steps

## Quick Start (Automated)

Run the automated deployment script:

```bash
cd AuthorizationManager/k8s
./deploy-authmanager.sh
```

This script will:
1. Verify/create Key Vault secrets
2. Verify/grant managed identity permissions
3. Update SecretProviderClass with correct values
4. Deploy AuthorizationManager to AKS

## Manual Steps

If you prefer to do it manually, follow these steps:

### Step 1: Ensure all secrets are set in Key Vault

```bash
# Set Key Vault name
KEYVAULT_NAME="your-keyvault-name"

# MySQL connection string (with SSL parameters)
az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "mysql-connection-string" \
  --value "jdbc:mysql://your-server.mysql.database.azure.com:3306/userdb?useSSL=true&requireSSL=true&verifyServerCertificate=false&serverTimezone=UTC&allowPublicKeyRetrieval=true"

# MySQL username
az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "mysql-username" \
  --value "your-username"

# MySQL password
az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "mysql-password" \
  --value "your-password"

# JWT secret
az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "jwt-secret" \
  --value "your-jwt-secret-key"
```

### Step 2: Verify managed identity has Key Vault access

```bash
# Set variables
RESOURCE_GROUP="your-resource-group"
AKS_CLUSTER="your-aks-cluster"
KEYVAULT_NAME="your-keyvault-name"

# Get managed identity client ID
MANAGED_IDENTITY_CLIENT_ID=$(az aks show \
  --name "$AKS_CLUSTER" \
  --resource-group "$RESOURCE_GROUP" \
  --query "identity.userAssignedIdentities.*.clientId" -o tsv | head -1)

# If using system-assigned identity:
# MANAGED_IDENTITY_CLIENT_ID=$(az aks show \
#   --name "$AKS_CLUSTER" \
#   --resource-group "$RESOURCE_GROUP" \
#   --query "identity.principalId" -o tsv)

# Get Key Vault resource ID
KEYVAULT_ID="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEYVAULT_NAME"

# Grant Key Vault Secrets User role
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee "$MANAGED_IDENTITY_CLIENT_ID" \
  --scope "$KEYVAULT_ID"
```

### Step 3: Update SecretProviderClass

Edit `secretproviderclass.yaml` and replace placeholders:

```yaml
spec:
  parameters:
    userAssignedIdentityID: "<your-managed-identity-client-id>"
    keyvaultName: "<your-keyvault-name>"
    tenantId: "<your-tenant-id>"
```

Or use the setup script:
```bash
./setup-keyvault.sh
```

### Step 4: Deploy AuthorizationManager

```bash
# Get AKS credentials
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER"

# Delete existing SecretProviderClass to avoid update conflicts
kubectl delete secretproviderclass authmanager-azure-keyvault -n muzika --ignore-not-found=true

# Apply all manifests
kubectl apply -k .

# Apply SecretProviderClass
kubectl apply -f secretproviderclass.yaml

# Wait for deployment
kubectl rollout status deployment/authmanager -n muzika --timeout=300s
```

## Verification

After deployment, verify everything is working:

```bash
# Check pod status
kubectl get pods -n muzika -l app=authmanager

# Check logs
kubectl logs -f deployment/authmanager -n muzika

# Check service
kubectl get svc -n muzika authmanager

# Check if secrets are mounted
kubectl exec -n muzika deployment/authmanager -- ls -la /mnt/secrets-store
```

## Troubleshooting

### Pods stuck in Pending
- Check if Key Vault CSI driver is installed: `kubectl get pods -n kube-system -l app=secrets-store-csi-driver`
- Verify managed identity has Key Vault access (Step 2)

### Pods failing to start
- Check logs: `kubectl logs -n muzika deployment/authmanager`
- Verify secrets exist in Key Vault
- Check SecretProviderClass: `kubectl describe secretproviderclass authmanager-azure-keyvault -n muzika`

### Connection to MySQL fails
- Verify connection string has SSL parameters
- Check firewall rules on MySQL server
- Verify MySQL credentials in Key Vault

