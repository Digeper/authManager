# Setup Azure Key Vault for AuthorizationManager

## Step 1: Set Secrets in Azure Key Vault

Make sure these secrets exist in your Azure Key Vault with these exact names:

```bash
# Find your Key Vault name
az keyvault list --query "[].name" -o table

# Set the secrets (replace <VAULT_NAME> with your actual vault name)
az keyvault secret set \
  --vault-name <VAULT_NAME> \
  --name postgres-connection-string \
  --value "jdbc:postgresql://digeper.postgres.database.azure.com:5432/postgres?sslmode=require"

az keyvault secret set \
  --vault-name <VAULT_NAME> \
  --name postgres-username \
  --value "digeper"

az keyvault secret set \
  --vault-name <VAULT_NAME> \
  --name postgres-password \
  --value "TvajaMami31d"

az keyvault secret set \
  --vault-name <VAULT_NAME> \
  --name jwt-secret \
  --value "your-jwt-secret-key"
```

## Step 2: Get Required Values

You need these values to configure the SecretProviderClass:

```bash
# Get your Azure Tenant ID
az account show --query tenantId -o tsv

# Get your Key Vault name
az keyvault list --query "[].name" -o table

# Get your Managed Identity Client ID (if using user-assigned identity)
az identity list --query "[].{Name:name, ClientId:clientId}" -o table
```

## Step 3: Update SecretProviderClass

Edit `AuthorizationManager/k8s/secretproviderclass.yaml` and replace the placeholders:

- `${KEYVAULT_NAME}` → Your Key Vault name
- `${TENANT_ID}` → Your Azure tenant ID  
- `${MANAGED_IDENTITY_CLIENT_ID}` → Your managed identity client ID (or leave empty if using system-assigned)

## Step 4: Delete Manual Secret

Delete the manual secret so the SecretProviderClass can create it from Key Vault:

```bash
kubectl delete secret authmanager-secrets -n muzika
```

## Step 5: Apply SecretProviderClass

```bash
kubectl apply -f AuthorizationManager/k8s/secretproviderclass.yaml
```

## Step 6: Verify Secret Created

```bash
# Check if secret was created by SecretProviderClass
kubectl get secret authmanager-secrets -n muzika

# Verify the secret has the correct keys
kubectl describe secret authmanager-secrets -n muzika
```

You should see:
- POSTGRES_URL
- POSTGRES_USERNAME
- POSTGRES_PASSWORD
- JWT_SECRET

## Step 7: Restart Deployment

```bash
kubectl rollout restart deployment/authmanager -n muzika
```

## Step 8: Verify Pod Starts

```bash
kubectl get pods -n muzika -l app=authmanager -w
kubectl logs -n muzika -l app=authmanager --tail=100 -f
```

## Troubleshooting

If the secret is not created:

1. **Check SecretProviderClass status:**
   ```bash
   kubectl describe secretproviderclass authmanager-azure-keyvault -n muzika
   ```

2. **Check pod events:**
   ```bash
   kubectl describe pod -n muzika -l app=authmanager | grep -A 10 Events
   ```

3. **Verify CSI driver is installed:**
   ```bash
   kubectl get pods -n kube-system | grep secrets-store
   ```

4. **Check managed identity permissions:**
   - The managed identity needs "Get" and "List" permissions on the Key Vault
   - In Azure Portal → Key Vault → Access policies → Add access policy
