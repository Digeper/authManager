# Apply Key Vault SecretProviderClass - Quick Steps

## Values You Have:
- Key Vault Name: `digeper`
- Tenant ID: `a6cc90df-f580-49dc-903f-87af5a75338e`
- Managed Identity Client ID: `156ce24f-4ed8-4b47-8088-b4e7a781dad2`

## Step 1: Verify Secrets Exist in Key Vault

```bash
# Check if secrets exist
az keyvault secret list --vault-name digeper --query "[].name" -o table
```

You should see:
- postgres-connection-string
- postgres-username
- postgres-password
- jwt-secret

If any are missing, create them:
```bash
az keyvault secret set --vault-name digeper --name postgres-connection-string --value "jdbc:postgresql://digeper.postgres.database.azure.com:5432/postgres?sslmode=require"
az keyvault secret set --vault-name digeper --name postgres-username --value "digeper"
az keyvault secret set --vault-name digeper --name postgres-password --value "TvajaMami31d"
az keyvault secret set --vault-name digeper --name jwt-secret --value "your-jwt-secret-key"
```

## Step 2: Apply SecretProviderClass

```bash
kubectl apply -f AuthorizationManager/k8s/secretproviderclass-applied.yaml
```

## Step 3: Delete Manual Secret

```bash
kubectl delete secret authmanager-secrets -n muzika
```

## Step 4: Verify Secret Created from Key Vault

```bash
# Wait a few seconds for the secret to be created
sleep 5

# Check if secret exists
kubectl get secret authmanager-secrets -n muzika

# Verify it has the correct keys
kubectl describe secret authmanager-secrets -n muzika
```

## Step 5: Restart Deployment

```bash
kubectl rollout restart deployment/authmanager -n muzika
```

## Step 6: Monitor Pod Startup

```bash
kubectl get pods -n muzika -l app=authmanager -w
```

In another terminal:
```bash
kubectl logs -n muzika -l app=authmanager --tail=100 -f
```

## Troubleshooting

If the secret is not created:

1. **Check SecretProviderClass:**
   ```bash
   kubectl describe secretproviderclass authmanager-azure-keyvault -n muzika
   ```

2. **Check pod events:**
   ```bash
   kubectl describe pod -n muzika -l app=authmanager | grep -A 10 Events
   ```

3. **Verify managed identity has Key Vault permissions:**
   - Go to Azure Portal → Key Vault `digeper` → Access policies
   - Ensure the managed identity `azurekeyvaultsecretsprovider-digeper` has "Get" and "List" permissions
