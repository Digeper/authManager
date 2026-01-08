# Node Just Redeployed - Next Steps

## Current Status

Your node was **just redeployed 2-3 minutes ago** (boot id: `51a27e77-4325-4a2c-96c6-4049e67a5467`). It's still initializing.

## Option 1: Wait 5-10 More Minutes (Recommended First)

The node needs time to fully initialize after redeploy:

1. **Containerd starting** (2m43s ago) - should finish soon
2. **CNI plugin initialization** - typically takes 2-5 minutes after containerd
3. **Node becoming Ready** - happens after CNI is initialized

**Wait 5-10 minutes and check:**

```bash
# Check if node is Ready now
kubectl get nodes

# If still NotReady, check why
kubectl describe node $(kubectl get nodes -o jsonpath='{.items[0].metadata.name}') | grep -A 15 "Conditions:"
```

**If after 10-15 minutes total, the node still shows:**
- `InvalidDiskCapacity` - This indicates a deeper issue
- `NetworkNotReady` / CNI not initialized - Also related to disk/filesystem

Then proceed to **Option 2**.

## Option 2: Upgrade Node Pool (Forces Fresh VMSS Image)

If the `InvalidDiskCapacity` error persists after waiting, the VMSS (Virtual Machine Scale Set) image itself may be corrupted. Upgrade the node pool to get a fresh image:

```bash
RESOURCE_GROUP="digeper"
AKS_CLUSTER_NAME="digeper-aks"

# Get current Kubernetes version
K8S_VERSION=$(az aks show \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --query kubernetesVersion -o tsv)

echo "Current K8s version: $K8S_VERSION"

# Upgrade node pool (this forces VMSS image refresh)
az aks nodepool upgrade \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name nodepool1 \
    --kubernetes-version $K8S_VERSION

# Monitor upgrade
az aks nodepool show \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name nodepool1 \
    --query "{provisioningState:provisioningState,powerState:powerState,count:count}"
```

## Option 3: Create New Node Pool with Different Configuration

If upgrade doesn't work, create a completely new node pool:

```bash
RESOURCE_GROUP="digeper"
AKS_CLUSTER_NAME="digeper-aks"

# Create new node pool
az aks nodepool add \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name nodepool2 \
    --node-count 1 \
    --node-vm-size Standard_DS2_v2 \
    --mode User

# Wait for new node to be Ready
kubectl get nodes -w

# Once new node is Ready, you can delete old pool (if you want)
# But you need at least one pool, so keep both or scale old one to 0 first
```

## Understanding InvalidDiskCapacity Error

`InvalidDiskCapacity 0 on image filesystem` means:
- The container image filesystem mounted on the node shows 0 capacity
- This prevents containerd from properly managing container images
- Without working filesystem, CNI can't initialize (needs containers to run)
- Without CNI, node can't become Ready

**This typically means:**
1. **VMSS image corruption** - The base VM image is corrupted
2. **Disk mount issues** - Container runtime disk isn't mounting correctly
3. **Storage/disk provisioning problems** - Azure storage issues

## Recommended Action Plan

**Right Now (Node just redeployed 2-3 min ago):**
1. ⏰ **Wait 5-10 minutes** for full initialization
2. Check node status: `kubectl get nodes`
3. If node becomes Ready → Great! Proceed with deployment
4. If node still NotReady after 10-15 min total → Try Option 2 (upgrade)

**If upgrade doesn't work:**
- Use Option 3 (new node pool)
- Or contact Azure support - this may be an Azure platform issue

## Quick Status Check

```bash
# One-liner to check if node is Ready
kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}'

# Should output: "True" when ready

# Check CNI/Network status specifically
kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="NetworkUnavailable")].status}'

# Should output: "False" when network is available (double negative - False means available)

# Use the diagnostic script
./AuthorizationManager/k8s/CHECK_CNI_PROGRESS.sh
```

## If CNI Still Not Initializing After 10-15 Minutes

If you've been seeing `NetworkNotReady` / `CNI plugin not initialized` for 10-15+ minutes:

1. **Check if InvalidDiskCapacity is still present:**
   ```bash
   kubectl describe node $(kubectl get nodes -o jsonpath='{.items[0].metadata.name}') | grep -i "disk\|capacity"
   ```
   - If **still present** → Try Option 2 (upgrade node pool)
   - If **gone** but CNI still not working → May be Azure platform issue

2. **Try upgrading the node pool** (Option 2 above) - this forces a complete VMSS refresh

3. **If upgrade doesn't work**, the VMSS image may be corrupted at the Azure level:
   - Contact Azure support
   - Or try creating a completely new AKS cluster
   - Or use a different VM size/configuration

