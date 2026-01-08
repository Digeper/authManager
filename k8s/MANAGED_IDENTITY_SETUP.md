# Fixing Managed Identity for Key Vault Access

## Problem

Error: `ManagedIdentityCredential authentication failed. the requested identity isn't assigned to this resource`

This means the managed identity either:
1. Isn't assigned to the AKS cluster
2. Doesn't have access to the Key Vault
3. The wrong identity ID is configured in SecretProviderClass

## Quick Fix

### Option 1: Use Automated Script

```bash
# Grant access using the script
./AuthorizationManager/k8s/FIX_MANAGED_IDENTITY.sh <YOUR_KEYVAULT_NAME>

# Example:
./AuthorizationManager/k8s/FIX_MANAGED_IDENTITY.sh muzika-keyvault
```

### Option 2: Manual Steps

**Step 1: Get AKS Cluster Managed Identity**

```bash
RESOURCE_GROUP="Digeper"
AKS_CLUSTER_NAME="Digeper-aks"

# Get the principal ID
PRINCIPAL_ID=$(az aks show \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --query "identity.principalId" -o tsv)

echo "Principal ID: $PRINCIPAL_ID"
```

**Step 2: Grant Key Vault Access**

```bash
KEYVAULT_NAME="<your-keyvault-name>"
KEYVAULT_ID=$(az keyvault show \
    --name $KEYVAULT_NAME \
    --query "id" -o tsv)

# Grant "Key Vault Secrets User" role
az role assignment create \
    --role "Key Vault Secrets User" \
    --assignee $PRINCIPAL_ID \
    --scope $KEYVAULT_ID
```

**Step 3: Verify SecretProviderClass Configuration**

Check that `AuthorizationManager/k8s/secret.yaml` has the correct managed identity:

```yaml
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "<MANAGED_IDENTITY_CLIENT_ID>"  # Should match AKS identity
    keyvaultName: "<your-keyvault-name>"
    tenantId: "<your-tenant-id>"
```

**Step 4: Restart Pods**

```bash
kubectl delete pods -n muzika -l app=authmanager
```

## Understanding Managed Identity Types

### System-Assigned Identity (Default for AKS)

- Automatically created with AKS cluster
- Principal ID is in `az aks show --query "identity.principalId"`

**For system-assigned identity:**
```yaml
parameters:
  useVMManagedIdentity: "true"
  userAssignedIdentityID: ""  # Empty for system-assigned
```

### User-Assigned Identity

- Created separately and assigned to AKS
- Need to provide client ID

**For user-assigned identity:**
```yaml
parameters:
  useVMManagedIdentity: "true"
  userAssignedIdentityID: "<CLIENT_ID>"  # User-assigned identity client ID
```

## Check Current Configuration

```bash
# 1. Check AKS identity type
az aks show \
    --resource-group Digeper \
    --name Digeper-aks \
    --query "identity" -o json

# 2. Check Key Vault access
PRINCIPAL_ID=$(az aks show --resource-group Digeper --name Digeper-aks --query "identity.principalId" -o tsv)
KEYVAULT_ID=$(az keyvault show --name <keyvault-name> --query "id" -o tsv)

az role assignment list \
    --assignee $PRINCIPAL_ID \
    --scope $KEYVAULT_ID

# 3. Check SecretProviderClass
kubectl get secretproviderclass authmanager-azure-keyvault -n muzika -o yaml
```

## Troubleshooting

### If Principal ID is empty:

Your cluster might not have managed identity enabled:

```bash
az aks update \
    --resource-group Digeper \
    --name Digeper-aks \
    --enable-managed-identity
```

### If using Workload Identity instead:

You'll need to:
1. Enable Workload Identity on AKS
2. Configure ServiceAccount annotation
3. Use different SecretProviderClass parameters

### Temporary Workaround: Use Manual Secrets

If you want to deploy without Key Vault for now:

```bash
# Create secrets manually
kubectl create secret generic authmanager-secrets -n muzika \
  --from-literal=MYSQL_URL='<url>' \
  --from-literal=MYSQL_USERNAME='<user>' \
  --from-literal=MYSQL_PASSWORD='<pass>' \
  --from-literal=JWT_SECRET='<secret>'

# Comment out Key Vault volume mount in deployment.yaml
# Then redeploy
```

## Verify Fix

After granting access and restarting pods:

```bash
# Check pod status
kubectl get pods -n muzika -l app=authmanager

# Check events for errors
kubectl get events -n muzika --sort-by='.lastTimestamp' | tail -10

# Check pod logs
kubectl logs -n muzika -l app=authmanager
```

If you see `FailedMount` errors about managed identity, the identity still doesn't have access or the wrong ID is configured.

