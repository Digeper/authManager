# Check and Update SecretProviderClass

## Step 1: Check Current SecretProviderClass Configuration

```bash
kubectl get secretproviderclass authmanager-azure-keyvault -n muzika -o yaml
```

Look for:
- `keyvaultName: "${KEYVAULT_NAME}"` - Should be `digeper`
- `tenantId: "${TENANT_ID}"` - Should be `a6cc90df-f580-49dc-903f-87af5a75338e`
- `userAssignedIdentityID: "${MANAGED_IDENTITY_CLIENT_ID}"` - Should be `156ce24f-4ed8-4b47-8088-b4e7a781dad2`

If you see placeholders (${...}), the SecretProviderClass needs to be updated.

## Step 2: Update SecretProviderClass

If it has placeholders, delete and recreate with actual values:

```bash
# Delete the old one
kubectl delete secretproviderclass authmanager-azure-keyvault -n muzika

# Apply the new one with actual values
kubectl apply -f AuthorizationManager/k8s/secretproviderclass-applied.yaml
```

## Step 3: Verify Secrets in Key Vault

```bash
az keyvault secret list --vault-name digeper --query "[].name" -o table
```

Should show:
- postgres-connection-string
- postgres-username
- postgres-password
- jwt-secret

## Step 4: Check Pod Status

The secret is created when a pod starts. Check if there's a pod:

```bash
kubectl get pods -n muzika -l app=authmanager
```

If a pod exists, check its events for CSI driver errors:

```bash
kubectl describe pod -n muzika -l app=authmanager | grep -A 20 Events
```

## Step 5: Verify Managed Identity Permissions

The managed identity needs Key Vault access. Check in Azure Portal:
- Key Vault `digeper` → Access policies
- Ensure identity `azurekeyvaultsecretsprovider-digeper` (156ce24f-4ed8-4b47-8088-b4e7a781dad2) has:
  - "Get" permission for secrets
  - "List" permission for secrets
