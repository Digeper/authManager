# Network Configuration Issues - Common Problems and Fixes

## How Network Issues Can Cause InvalidDiskCapacity

If your AKS network is misconfigured, the CNI (Container Network Interface) plugin cannot initialize. This causes:
- `NetworkNotReady` errors
- CNI pods can't start
- Container runtime can't properly mount filesystems
- Leads to `InvalidDiskCapacity` errors as a symptom

**The root cause might be network, not disk!**

## Important: Overlay Mode vs Traditional Azure CNI

**Your cluster uses Azure CNI in overlay mode:**
- ✅ Pods don't need IPs from VNet subnet (they use overlay networking)
- ⚠️ But nodes still need IPs from subnet
- ⚠️ Subnet still needs proper delegation
- ⚠️ Network configuration still matters for CNI initialization

## Quick Check

Run the network diagnostic:
```bash
./AuthorizationManager/k8s/CHECK_NETWORK_CONFIG.sh
```

## Common Network Configuration Issues

### Issue 1: Subnet Too Small or Misconfigured

**Symptom:** Even in overlay mode, subnet issues can prevent CNI initialization

**Check actual subnet:**
```bash
# Find the actual subnet being used
./AuthorizationManager/k8s/CHECK_ACTUAL_SUBNET.sh

# Or manually check
MC_RG="MC_Digeper_Digeper-aks_italynorth"  # Managed resource group
az network vnet list --resource-group $MC_RG
```

**For Overlay Mode:**
- Nodes still need IPs from subnet (pods don't)
- Need subnet with at least /24 (256 IPs) for nodes
- Even though pods use overlay, subnet must still be properly configured

**Fix:**
```bash
# If subnet is too small or has issues:
# 1. Ensure subnet has at least /24 for nodes
# 2. Ensure proper delegation (see Issue 2)
# 3. Check subnet in managed resource group (MC_*)
```

### Issue 2: Missing Subnet Delegation (Azure CNI)

**Symptom:** CNI can't configure networking on subnet

**Check:**
```bash
az network vnet subnet show \
    --resource-group <RG> \
    --vnet-name <VNET> \
    --name <SUBNET> \
    --query delegations
```

**Should show:**
```json
[{
  "name": "Microsoft.ContainerService.managedClusters",
  "serviceName": "Microsoft.ContainerService/managedClusters"
}]
```

**Fix:**
```bash
az network vnet subnet update \
    --resource-group <RG> \
    --vnet-name <VNET> \
    --name <SUBNET> \
    --delegations Microsoft.ContainerService/managedClusters
```

### Issue 3: Network Security Group Blocking Ports

**Symptom:** Required services can't communicate

**Check:**
```bash
# Get NSG on subnet
NSG_ID=$(az network vnet subnet show \
    --resource-group <RG> \
    --vnet-name <VNET> \
    --name <SUBNET> \
    --query "networkSecurityGroup.id" -o tsv)

if [ -n "$NSG_ID" ]; then
    az network nsg rule list --ids $NSG_ID
fi
```

**Required ports for AKS:**
- 443 (HTTPS)
- 10250 (Kubelet)
- 10255 (Read-only Kubelet)
- 53 (DNS)
- ICMP

**Fix:** Add NSG rules or remove blocking rules

### Issue 4: Service Principal Missing VNet Permissions

**Symptom:** AKS can't configure network resources

**Check:**
```bash
# Get service principal
SP_ID=$(az aks show \
    --resource-group <RG> \
    --name <AKS> \
    --query "servicePrincipalProfile.clientId" -o tsv)

# Check VNet permissions
VNET_ID=$(az network vnet subnet show \
    --resource-group <RG> \
    --vnet-name <VNET> \
    --name <SUBNET> \
    --query "id" -o tsv | sed 's|/subnets/.*||')

az role assignment list \
    --assignee $SP_ID \
    --scope $VNET_ID
```

**Fix:**
```bash
# Grant Contributor role on VNet
az role assignment create \
    --role Contributor \
    --assignee $SP_ID \
    --scope $VNET_ID
```

### Issue 5: VNet and Cluster in Different Resource Groups

**Symptom:** AKS can't find or access VNet resources

**Fix:** Ensure service principal has access to VNet resource group

```bash
# Grant Contributor on VNet resource group
VNET_RG="<VNet-Resource-Group>"
az role assignment create \
    --role Contributor \
    --assignee $SP_ID \
    --scope /subscriptions/<sub-id>/resourceGroups/$VNET_RG
```

### Issue 6: Incorrect Network Plugin Configuration

**Symptom:** CNI plugin mismatch or misconfiguration

**Check:**
```bash
az aks show \
    --resource-group <RG> \
    --name <AKS> \
    --query "networkProfile.networkPlugin" -o tsv
```

**Fix:** If misconfigured, you may need to recreate cluster or switch network plugin:

```bash
# Switch to kubenet (simpler, if you don't need Azure CNI features)
az aks update \
    --resource-group <RG> \
    --name <AKS> \
    --network-plugin kubenet
```

**Note:** Changing network plugin after cluster creation requires careful planning or cluster recreation.

## Quick Diagnosis Commands

```bash
# 1. Check network plugin
az aks show --resource-group <RG> --name <AKS> --query "networkProfile.networkPlugin"

# 2. Check subnet size
az network vnet subnet show --resource-group <RG> --vnet-name <VNET> --name <SUBNET> --query "addressPrefix"

# 3. Check subnet delegation
az network vnet subnet show --resource-group <RG> --vnet-name <VNET> --name <SUBNET> --query delegations

# 4. Check node pool max pods
az aks nodepool show --resource-group <RG> --cluster-name <AKS> --name <NODEPOOL> --query maxPods

# 5. Calculate required IPs: nodes × maxPods + overhead
# Example: 3 nodes × 30 pods = 90 IPs minimum (need subnet with 100+ IPs)
```

## Recommendation

**If you're just getting started and don't need Azure CNI features:**

Consider using **kubenet** instead - it's simpler and doesn't require:
- Large subnets
- Subnet delegation
- Complex IP management

However, if you already have a cluster, switching requires recreation.

## Next Steps

1. **Run the network diagnostic:** `./CHECK_NETWORK_CONFIG.sh`
2. **Identify the specific issue** from the output
3. **Apply the appropriate fix** from above
4. **Restart node pool** after fixing network configuration:
   ```bash
   az aks nodepool scale --resource-group <RG> --cluster-name <AKS> --name <NODEPOOL> --node-count 0
   # Wait 2 minutes
   az aks nodepool scale --resource-group <RG> --cluster-name <AKS> --name <NODEPOOL> --node-count 1
   ```

