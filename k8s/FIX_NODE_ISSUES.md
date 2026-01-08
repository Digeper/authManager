# Fix Node NotReady with Multiple Issues

## Current Problems

1. **InvalidDiskCapacity** - `invalid capacity 0 on image filesystem`
2. **CoreDNSUnreachable** - DNS failing (CNI not working)
3. **ContainerdStart** - Container runtime not fully ready
4. **Node NotReady** - Node stuck in NotReady despite multiple auto-repair attempts

## Immediate Solution: Replace the Node Pool

The node has been auto-repaired (rebooted/reimaged/redeployed) multiple times but still won't become Ready. The best solution is to **replace the node pool entirely**.

### Option 1: Scale to 0 then Back Up (Recommended - Works with Single Node Pool)

**Note:** You cannot delete the only node pool in a cluster. Instead, scale it to 0 which will delete all nodes, then scale back up to create new nodes.

```bash
RESOURCE_GROUP="digeper"  # Based on your ProviderID
AKS_CLUSTER_NAME="digeper-aks"  # Based on your resource group name
NODEPOOL_NAME="nodepool1"

# Scale down to 0 (deletes all nodes but keeps the node pool)
az aks nodepool scale \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name $NODEPOOL_NAME \
    --node-count 0

# Wait 3-5 minutes for nodes to be fully deleted
# Check status:
az aks nodepool show \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name $NODEPOOL_NAME \
    --query "count" -o tsv
# Should show 0

# Scale back up (creates new nodes with fresh filesystems)
az aks nodepool scale \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name $NODEPOOL_NAME \
    --node-count 3

# Monitor nodes coming up (takes 5-10 minutes)
kubectl get nodes -w
```

**Timeline:** 10-15 minutes

### Option 2: Create New Node Pool, Then Delete Old One (If You Have Multiple Node Pools)

```bash
RESOURCE_GROUP="digeper"
AKS_CLUSTER_NAME="digeper-aks"

# Scale down to 0 (deletes the problematic node)
az aks nodepool scale \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name nodepool1 \
    --node-count 0

# Wait 3-5 minutes for node deletion

# Scale back up (creates new nodes)
az aks nodepool scale \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name nodepool1 \
    --node-count 3

# Monitor nodes
kubectl get nodes -w
```

**Timeline:** 10-15 minutes

### Option 3: Upgrade Node Pool (Triggers Node Replacement)

```bash
RESOURCE_GROUP="digeper"
AKS_CLUSTER_NAME="digeper-aks"

# Get current Kubernetes version
K8S_VERSION=$(az aks show \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --query kubernetesVersion -o tsv)

# Upgrade node pool (forces node replacement)
az aks nodepool upgrade \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name nodepool1 \
    --kubernetes-version $K8S_VERSION \
    --no-wait

# Monitor upgrade progress
az aks nodepool show \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name nodepool1 \
    --query "provisioningState"
```

## Understanding Node Taints

When a node is `NotReady`, Kubernetes automatically adds a taint `node.kubernetes.io/not-ready` to prevent new pods from scheduling. This is **normal behavior** and protects against scheduling pods on unhealthy nodes.

**The taint will automatically be removed** once the node becomes Ready.

### Check Node Status

```bash
# Check if node is Ready
kubectl get nodes

# Check node conditions in detail
kubectl describe node $(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# Check why pods are pending
kubectl describe pod <pod-name> -n <namespace>
```

**If node shows Ready but pods still can't schedule:**
- Wait a minute - taint removal can take a moment
- Or manually remove taint (not recommended, but possible):
  ```bash
  kubectl taint nodes <node-name> node.kubernetes.io/not-ready:NoSchedule-
  ```

**If node is still NotReady after 10-15 minutes:**
- The node may have persistent issues
- Consider scaling to 0 and back up again

## Verify Fix

```bash
# Check node status - should show Ready
kubectl get nodes

# Should see:
# NAME                                STATUS   ROLES   AGE   VERSION
# aks-nodepool1-xxxx-vmss000000       Ready    <none>  5m    v1.33.5
# aks-nodepool1-xxxx-vmss000001       Ready    <none>  5m    v1.33.5
# aks-nodepool1-xxxx-vmss000002       Ready    <none>  5m    v1.33.5

# Check node conditions - should see all True
kubectl describe nodes | grep -A 10 "Conditions:"

# Check system pods starting
kubectl get pods -n kube-system

# Check CoreDNS is reachable now
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Should show Running status
```

## Important: Single Node Considerations

**If you're using only 1 node:**

1. **Pod Anti-Affinity Issues**: Your AuthorizationManager deployment has pod anti-affinity rules that prefer pods on different nodes. With 1 node, pods will still schedule but anti-affinity won't have effect.

2. **No Redundancy**: If the single node fails, your entire application goes down.

3. **Resource Constraints**: All pods run on one node - make sure it has enough resources.

4. **Deployment Replicas**: With 1 node and 2 replicas (default), both pods will run on the same node (which is fine, just less redundancy).

**Recommendation:**
- For **testing/development**: 1 node is fine
- For **production**: Use at least 2-3 nodes for redundancy

If you need to temporarily reduce replicas for single node:
```bash
# Reduce to 1 replica if you have resource constraints on single node
kubectl scale deployment authmanager -n muzika --replicas=1
```

## Root Cause Analysis

The issues indicate:
1. **Disk/filesystem corruption** - `InvalidDiskCapacity 0` suggests the image filesystem has issues
2. **CNI not initializing** - Because of the disk/filesystem issue
3. **CoreDNS failing** - Because CNI can't provide network connectivity
4. **Auto-repair loop** - AKS keeps trying to fix it but the underlying issue persists

This typically happens when:
- Node OS disk gets corrupted
- VMSS (Virtual Machine Scale Set) image is corrupted
- Underlying Azure storage issues
- Node was improperly shut down or had a hard failure

## Prevention

1. **Enable auto-scaling** to spread load across nodes
2. **Use multiple node pools** for redundancy
3. **Monitor node health** regularly
4. **Keep cluster updated** to latest Kubernetes version

```bash
# Enable cluster autoscaler
az aks nodepool update \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name nodepool1 \
    --enable-cluster-autoscaler \
    --min-count 2 \
    --max-count 5
```

