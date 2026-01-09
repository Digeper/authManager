# Troubleshoot SecretProviderClass Secret Creation

The secret `authmanager-secrets` is not being created from Key Vault. Let's troubleshoot:

## Step 1: Check if SecretProviderClass is Applied

```bash
kubectl get secretproviderclass authmanager-azure-keyvault -n muzika
```

If it doesn't exist, apply it:
```bash
kubectl apply -f AuthorizationManager/k8s/secretproviderclass-applied.yaml
```

## Step 2: Check SecretProviderClass Details

```bash
kubectl describe secretproviderclass authmanager-azure-keyvault -n muzika
```

Look for any errors or warnings.

## Step 3: Verify Secrets Exist in Key Vault

```bash
az keyvault secret list --vault-name digeper --query "[].name" -o table
```

Make sure these exist:
- postgres-connection-string
- postgres-username
- postgres-password
- jwt-secret

## Step 4: Check Pod Status

The CSI driver creates the secret when a pod using it starts. Check if there's a pod:

```bash
kubectl get pods -n muzika -l app=authmanager
```

If no pod exists, the secret won't be created yet. The secret is created when the pod starts and mounts the volume.

## Step 5: Check Pod Events

If a pod exists, check its events for CSI driver errors:

```bash
kubectl describe pod -n muzika -l app=authmanager | grep -A 20 Events
```

Look for errors related to:
- secrets-store-csi-driver
- Key Vault access
- Managed identity

## Step 6: Verify Managed Identity Permissions

The managed identity `azurekeyvaultsecretsprovider-digeper` needs permissions on the Key Vault:

```bash
# Check Key Vault access policies (via Azure Portal or CLI)
az keyvault show --name digeper --query "properties.accessPolicies" -o table
```

The identity `156ce24f-4ed8-4b47-8088-b4e7a781dad2` needs:
- "Get" permission for secrets
- "List" permission for secrets

## Step 7: Manual Secret Creation (Temporary Workaround)

If the SecretProviderClass isn't working, you can temporarily create the secret manually again:

```bash
kubectl create secret generic authmanager-secrets \
  --namespace=muzika \
  --from-literal=POSTGRES_URL='jdbc:postgresql://digeper.postgres.database.azure.com:5432/postgres?sslmode=require' \
  --from-literal=POSTGRES_USERNAME='digeper' \
  --from-literal=POSTGRES_PASSWORD='TvajaMami31d' \
  --from-literal=JWT_SECRET='your-jwt-secret-key'
```

Then restart the deployment to get it working, and troubleshoot the Key Vault integration separately.

## Common Issues

1. **SecretProviderClass not applied** - Apply it first
2. **Secrets don't exist in Key Vault** - Create them
3. **Managed identity lacks permissions** - Grant Key Vault access
4. **CSI driver not installed** - Check if secrets-store-csi-driver is running
5. **Pod not running** - The secret is only created when a pod mounts the volume
