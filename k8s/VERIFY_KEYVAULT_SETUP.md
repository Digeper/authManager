# Verify Key Vault Setup

The SecretProviderClass is configured correctly. Now we need to verify:

## Step 1: Verify Secrets Exist in Key Vault

```bash
az keyvault secret list --vault-name digeper --query "[].name" -o table
```

Should show:
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

## Step 2: Check Pod Status

The secret is created when a pod starts. Check if there's a pod:

```bash
kubectl get pods -n muzika -l app=authmanager
```

If no pod exists, create a manual secret temporarily to get the pod running, then the SecretProviderClass will take over on the next restart.

## Step 3: Check Pod Events (if pod exists)

If a pod exists but the secret isn't created, check for CSI driver errors:

```bash
kubectl describe pod -n muzika -l app=authmanager | grep -A 30 Events
```

Look for errors related to:
- secrets-store-csi-driver
- Key Vault access denied
- Managed identity issues

## Step 4: Verify Managed Identity Permissions

The managed identity `azurekeyvaultsecretsprovider-digeper` (156ce24f-4ed8-4b47-8088-b4e7a781dad2) needs Key Vault permissions.

Check in Azure Portal:
1. Go to Key Vault `digeper` → Access policies
2. Find the identity with Client ID `156ce24f-4ed8-4b47-8088-b4e7a781dad2`
3. Ensure it has:
   - ✅ "Get" permission for secrets
   - ✅ "List" permission for secrets

Or via CLI:
```bash
az keyvault show --name digeper --query "properties.accessPolicies[?objectId=='<OBJECT_ID>']" -o table
```

## Step 5: Temporary Workaround

To get the application running immediately while troubleshooting Key Vault:

```bash
kubectl create secret generic authmanager-secrets \
  --namespace=muzika \
  --from-literal=POSTGRES_URL='jdbc:postgresql://digeper.postgres.database.azure.com:5432/postgres?sslmode=require' \
  --from-literal=POSTGRES_USERNAME='digeper' \
  --from-literal=POSTGRES_PASSWORD='TvajaMami31d' \
  --from-literal=JWT_SECRET='your-jwt-secret-key'
```

Then restart:
```bash
kubectl rollout restart deployment/authmanager -n muzika
```

This gets the app working. Once working, you can delete the manual secret and troubleshoot why the SecretProviderClass isn't creating it automatically.
