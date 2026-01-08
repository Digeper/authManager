# Fix CNI Plugin Not Initialized - Quick Guide

## Problem
Nodes show: `NetworkNotReady=false reason:NetworkPluginNotReady message:Network plugin returns error: cni plugin not initialized`

This prevents ALL pods from starting.

## Quick Fix (Fastest)

### Option 1: Restart Node Pool (5-10 minutes)

```bash
# Set variables
RESOURCE_GROUP="muzika-rg"
AKS_CLUSTER_NAME="muzika-aks"
NODEPOOL_NAME="nodepool1"

# Scale to 0 (drains and deletes nodes)
az aks nodepool scale \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name $NODEPOOL_NAME \
    --node-count 0

# Wait 2-3 minutes, then scale back up
az aks nodepool scale \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name $NODEPOOL_NAME \
    --node-count 3

# Monitor nodes coming back up (wait 5-10 minutes)
watch kubectl get nodes
```

### Option 2: Upgrade Node Pool Kubernetes Version

```bash
# Get current version
az aks show \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --query kubernetesVersion -o tsv

# Upgrade node pool (triggers node replacement)
az aks nodepool upgrade \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name $NODEPOOL_NAME \
    --kubernetes-version $(az aks show \
        --resource-group $RESOURCE_GROUP \
        --name $AKS_CLUSTER_NAME \
        --query kubernetesVersion -o tsv)
```

## Verify Fix

```bash
# Check node status (should show Ready, not NetworkNotReady)
kubectl get nodes

# Check node conditions
kubectl describe nodes | grep -A 5 "Conditions:"

# Should see: NetworkReady=True

# Wait for system pods to start
kubectl get pods -n kube-system -w

# Once CNI is ready, system pods should start
# Then your application pods can start
```

## If Fix Doesn't Work

### Check Subnet IP Availability

```bash
# Check cluster network profile
az aks show \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --query "networkProfile"

# Check subnet IP usage
az network vnet subnet show \
    --resource-group <VNET_RESOURCE_GROUP> \
    --vnet-name <VNET_NAME> \
    --name <SUBNET_NAME> \
    --query "addressPrefix"
```

If subnet is out of IPs, you need to:
1. Use a larger subnet, OR
2. Switch to kubenet networking mode, OR
3. Reduce max pods per node

### Create New Node Pool

If the existing node pool is corrupted:

```bash
# Create new node pool
az aks nodepool add \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name nodepool2 \
    --node-count 3 \
    --node-vm-size Standard_DS2_v2 \
    --mode User

# Once new nodes are ready, delete old pool
az aks nodepool delete \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name $NODEPOOL_NAME
```

## Expected Timeline

- Node pool restart: 5-10 minutes
- CNI initialization: 2-5 minutes after nodes are Ready
- System pods starting: 5-10 minutes total
- Application pods: Once system pods are running

**Total expected time: 15-25 minutes**

