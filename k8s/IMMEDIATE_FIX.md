# IMMEDIATE FIX: Corrupted VMSS Image

## Problem

The `InvalidDiskCapacity` error has persisted for **57+ minutes** across multiple node reboots/redeploys. This indicates the **VMSS (Virtual Machine Scale Set) base image is corrupted** at the Azure platform level.

**This will NOT fix itself** - you need to force Azure to use a fresh VMSS image.

## Solution: Upgrade Node Pool

Upgrading the node pool forces Azure to:
1. Create a new VMSS with a fresh image
2. Replace all nodes with new VMs from the fresh image
3. This resolves the corrupted image issue

### Quick Fix (Automated Script)

```bash
# Run the automated fix script
./AuthorizationManager/k8s/FIX_CORRUPTED_VMSS.sh
```

The script will:
- Get current Kubernetes version
- Upgrade the node pool (forces fresh VMSS image)
- Monitor progress
- Wait for nodes to become Ready
- Verify no more InvalidDiskCapacity errors

### Manual Fix

```bash
RESOURCE_GROUP="digeper"
AKS_CLUSTER_NAME="digeper-aks"

# Get current K8s version
K8S_VERSION=$(az aks show \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --query kubernetesVersion -o tsv)

echo "Current version: $K8S_VERSION"

# Upgrade node pool (forces VMSS refresh)
az aks nodepool upgrade \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name nodepool1 \
    --kubernetes-version $K8S_VERSION

# Monitor progress (check every 30 seconds)
watch -n 30 'az aks nodepool show \
    --resource-group '$RESOURCE_GROUP' \
    --cluster-name '$AKS_CLUSTER_NAME' \
    --name nodepool1 \
    --query "{provisioningState:provisioningState,count:count}"'

# Once provisioningState shows "Succeeded", check nodes
kubectl get nodes -w
```

## Timeline

- **Upgrade initiation**: Immediate
- **VMSS refresh**: 5-10 minutes
- **New nodes created**: 5-10 minutes  
- **Nodes become Ready**: 10-15 minutes total

## Verification

After upgrade completes, verify:

```bash
# Check nodes are Ready
kubectl get nodes

# Should show: STATUS = Ready (not NotReady)

# Check no InvalidDiskCapacity errors
kubectl describe nodes | grep -i "InvalidDiskCapacity"

# Should return nothing (no errors)

# Check CNI is working (no NetworkNotReady)
kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="NetworkUnavailable")].status}'

# Should output: "False" (meaning network IS available)
```

## Why This Works

- **Redeploy/Reboot**: Only restarts the same corrupted VM image
- **Scale to 0 and back**: Creates new VMs but from the same corrupted VMSS image
- **Upgrade**: Forces Azure to create a completely new VMSS with a fresh, validated image

The upgrade process ensures Azure uses the latest, validated VMSS image for your Kubernetes version.

## Alternative: Update VM Size (If Upgrade Doesn't Work)

If upgrading doesn't resolve the issue, try changing the VM size. This forces Azure to create new VMs:

```bash
RESOURCE_GROUP="digeper"
AKS_CLUSTER_NAME="digeper-aks"

# Update to a different VM size (forces node replacement)
az aks nodepool update \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name nodepool1 \
    --node-vm-size Standard_DS3_v2

# Or try a different size like:
# --node-vm-size Standard_DS2_v2
# --node-vm-size Standard_B2s
# --node-vm-size Standard_DS1_v2
```

## If Upgrade/Update Fails

If the upgrade/update fails or doesn't resolve the issue:

2. **Create a new node pool:**
   ```bash
   az aks nodepool add \
       --resource-group $RESOURCE_GROUP \
       --cluster-name $AKS_CLUSTER_NAME \
       --name nodepool2 \
       --node-count 1 \
       --node-vm-size Standard_DS2_v2
   ```

3. **Contact Azure Support** - This may indicate a broader platform issue

## Expected Result

After upgrade:
- ✅ Nodes show `Ready` status
- ✅ No `InvalidDiskCapacity` errors
- ✅ CNI initializes properly
- ✅ System pods (coredns, metrics-server) start
- ✅ Your AuthorizationManager pods can deploy

