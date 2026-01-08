# Troubleshooting Guide - Pods Stuck in Pending/ContainerCreating

## Common Issues and Solutions

### ⚠️ CRITICAL: CNI Plugin Not Initialized (NetworkNotReady)

**Error:** `NetworkReady=false reason:NetworkPluginNotReady message:Network plugin returns error: cni plugin not initialized`

This is a **cluster-level networking issue** that prevents ALL pods from starting. This must be fixed first.

#### Symptoms
- All pods stuck in Pending state
- Node status shows `NetworkNotReady`
- Events show `cni plugin not initialized`
- System pods (coredns, metrics-server, etc.) can't start

#### Diagnosis

```bash
# Check node conditions
kubectl get nodes -o wide
kubectl describe nodes | grep -A 10 "Conditions:"

# Check CNI pods
kubectl get pods -n kube-system | grep -i "network\|cni\|azure"

# Check kubelet logs on nodes (requires SSH access or node logs)
# Or check node events
kubectl get events --all-namespaces | grep -i "network\|cni"
```

#### Solutions

**Solution 1: Restart Node Pool (Recommended)**

```bash
# Get node pool name
az aks nodepool list \
    --resource-group <RESOURCE_GROUP> \
    --cluster-name <AKS_CLUSTER_NAME>

# Scale down to 0 (this will drain and delete nodes)
az aks nodepool scale \
    --resource-group <RESOURCE_GROUP> \
    --cluster-name <AKS_CLUSTER_NAME> \
    --name nodepool1 \
    --node-count 0

# Wait for nodes to be deleted, then scale back up
az aks nodepool scale \
    --resource-group <RESOURCE_GROUP> \
    --cluster-name <AKS_CLUSTER_NAME> \
    --name nodepool1 \
    --node-count 3

# Wait 5-10 minutes for nodes to come up and CNI to initialize
kubectl get nodes -w
```

**Solution 2: Delete and Recreate Node Pool**

```bash
# Delete the problematic node pool
az aks nodepool delete \
    --resource-group <RESOURCE_GROUP> \
    --cluster-name <AKS_CLUSTER_NAME> \
    --name nodepool1

# Create a new node pool
az aks nodepool add \
    --resource-group <RESOURCE_GROUP> \
    --cluster-name <AKS_CLUSTER_NAME> \
    --name nodepool1 \
    --node-count 3 \
    --node-vm-size Standard_DS2_v2
```

**Solution 3: Update AKS Cluster (May Fix CNI Issues)**

```bash
az aks upgrade \
    --resource-group <RESOURCE_GROUP> \
    --name <AKS_CLUSTER_NAME> \
    --kubernetes-version <LATEST_VERSION> \
    --control-plane-only

# After control plane upgrade, upgrade node pool
az aks nodepool upgrade \
    --resource-group <RESOURCE_GROUP> \
    --cluster-name <AKS_CLUSTER_NAME> \
    --name nodepool1 \
    --kubernetes-version <LATEST_VERSION>
```

**Solution 4: Check Azure CNI Configuration**

```bash
# Verify AKS cluster network configuration
az aks show \
    --resource-group <RESOURCE_GROUP> \
    --name <AKS_CLUSTER_NAME> \
    --query "networkProfile"

# If using Azure CNI, check subnet configuration
# Ensure subnet has enough IP addresses for pods
```

**Solution 5: Manual CNI Pod Restart (if accessible)**

```bash
# Try to restart CNI-related pods
kubectl delete pods -n kube-system -l k8s-app=azure-cni
kubectl delete pods -n kube-system -l component=kube-proxy

# Note: This may not work if CNI is completely broken
```

#### Root Causes

1. **Subnet IP exhaustion** - Azure CNI subnet ran out of IP addresses
2. **CNI DaemonSet failure** - CNI pods crashed or can't start
3. **Node OS issues** - Node OS corruption or networking stack issues
4. **AKS upgrade issues** - Failed or incomplete cluster upgrade
5. **Resource constraints** - Nodes too small for system pods + CNI

#### Prevention

1. **Use appropriate subnet size** for Azure CNI:
   ```bash
   # Ensure subnet has enough IPs: (node_count * max_pods_per_node) + overhead
   # Example: 3 nodes * 30 pods = 90 IPs needed + overhead
   ```

2. **Monitor node health**:
   ```bash
   kubectl get nodes
   kubectl top nodes
   ```

3. **Use kubenet instead of Azure CNI** for simpler setups (less IP management)

---

### Issue: All Pods Stuck in Pending State

If all pods (including system pods) are in Pending state, this usually indicates a cluster-wide resource issue.

#### 1. Check Node Status

```bash
kubectl get nodes -o wide
kubectl describe nodes
```

**Problems to look for:**
- Nodes in `NotReady` state
- Insufficient CPU/Memory
- Network issues (CNI plugin not initialized)
- Disk pressure
- `InvalidDiskCapacity 0 on image filesystem` - indicates disk/filesystem corruption
- `CoreDNSUnreachable` - usually caused by CNI issues
- Containerd not fully started

#### 2. Check Node Resources

```bash
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"
```

**Solutions:**
- Scale up your node pool if resources are exhausted
- Add more nodes: `az aks nodepool scale --resource-group <RG> --cluster-name <AKS> --name nodepool1 --node-count 3`

#### 3. Check Pod Events

```bash
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -50
kubectl describe pod <pod-name> -n <namespace>
```

Common error messages:
- `Insufficient cpu` - Need more CPU capacity
- `Insufficient memory` - Need more memory
- `0/3 nodes are available: 3 Insufficient cpu, 3 Insufficient memory` - Cluster is full

---

### Issue: Key Vault CSI Driver Not Starting

The `aks-secrets-store-csi-driver` pod stuck in ContainerCreating.

#### 1. Check Pod Events

```bash
kubectl describe pod -n kube-system -l app=secrets-store-csi-driver
```

#### 2. Common Causes

**Missing RBAC permissions:**
```bash
kubectl get clusterrole secrets-store-csi-driver
kubectl get clusterrolebinding secrets-store-csi-driver
```

**Node selector/tolerations mismatch:**
```bash
kubectl describe daemonset aks-secrets-store-csi-driver -n kube-system
```

**Solution - Re-enable the addon:**
```bash
az aks disable-addons \
    --resource-group <RESOURCE_GROUP> \
    --name <AKS_CLUSTER_NAME> \
    --addons azure-keyvault-secrets-provider

az aks enable-addons \
    --resource-group <RESOURCE_GROUP> \
    --name <AKS_CLUSTER_NAME> \
    --addons azure-keyvault-secrets-provider
```

---

### Issue: AuthorizationManager Pods Pending

If only authmanager pods are pending but other pods work:

#### 1. Check Resource Requests

```bash
kubectl describe pod -n muzika -l app=authmanager
```

Look for:
- `Insufficient cpu` or `Insufficient memory`
- Node selector mismatches
- Affinity/anti-affinity constraints

#### 2. Check for Taints/Tolerations

```bash
kubectl describe nodes | grep -i taint
```

If nodes have taints, add tolerations to deployment.

#### 3. Check Pod Affinity Rules

Your deployment has pod anti-affinity. If you have fewer than 2 nodes, pods may not schedule:

```bash
# Temporarily reduce replicas if needed
kubectl scale deployment authmanager -n muzika --replicas=1
```

Or remove anti-affinity for testing.

#### 4. Check SecretProviderClass

If pods are waiting for secrets from Key Vault:

```bash
kubectl describe secretproviderclass authmanager-azure-keyvault -n muzika
kubectl get secret authmanager-secrets -n muzika
```

**Temporary workaround - Use manual secrets instead of Key Vault:**

Edit `deployment.yaml` and comment out the Key Vault volume mount, then create secrets manually:

```bash
kubectl create secret generic authmanager-secrets -n muzika \
  --from-literal=MYSQL_URL='<your-url>' \
  --from-literal=MYSQL_USERNAME='<username>' \
  --from-literal=MYSQL_PASSWORD='<password>' \
  --from-literal=JWT_SECRET='<secret>'
```

---

### Issue: Pods Can't Pull Images

```bash
kubectl describe pod -n muzika -l app=authmanager | grep -i "failed\|error\|image"
```

**Solutions:**
- Check ACR pull permissions
- Verify image exists: `az acr repository show-tags --name <ACR> --repository muzika/authmanager`
- Check imagePullSecrets in deployment

---

### Quick Diagnostic Commands

```bash
# Overall cluster health
kubectl get nodes
kubectl get pods --all-namespaces

# Resource usage
kubectl top nodes
kubectl top pods --all-namespaces

# Check events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -30

# Check specific pod
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace> --previous

# Check CSI driver
kubectl get pods -n kube-system -l app=secrets-store-csi-driver
kubectl describe pod -n kube-system -l app=secrets-store-csi-driver

# Check SecretProviderClass
kubectl get secretproviderclass -n muzika
kubectl describe secretproviderclass authmanager-azure-keyvault -n muzika
```

---

### Emergency: Bypass Key Vault Temporarily

If Key Vault CSI driver is the issue and you need to get pods running:

1. Comment out Key Vault volume in deployment.yaml
2. Create Kubernetes secret manually
3. Deploy without Key Vault dependency

```bash
# Create namespace
kubectl create namespace muzika

# Create secrets manually
kubectl create secret generic authmanager-secrets -n muzika \
  --from-literal=MYSQL_URL='jdbc:mysql://...' \
  --from-literal=MYSQL_USERNAME='...' \
  --from-literal=MYSQL_PASSWORD='...' \
  --from-literal=JWT_SECRET='...'

# Deploy without SecretProviderClass
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/deployment.yaml  # (with Key Vault volume commented out)
```

