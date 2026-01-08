# How to Use kubectl with Azure AKS

## Prerequisites

1. **Azure CLI installed** and logged in
   ```bash
   az login
   az account list  # See available subscriptions
   az account set --subscription <SUBSCRIPTION_ID>  # Set active subscription
   ```

2. **kubectl installed**
   - macOS: `brew install kubectl`
   - Linux: `az aks install-cli`
   - Or download from: https://kubernetes.io/docs/tasks/tools/

## Get kubectl Credentials for AKS

### Method 1: Using Azure CLI (Recommended)

```bash
# Set your variables
RESOURCE_GROUP="muzika-rg"  # Replace with your resource group
AKS_CLUSTER_NAME="muzika-aks"  # Replace with your AKS cluster name

# Get credentials and configure kubectl
az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME

# Verify connection
kubectl get nodes
```

This will:
- Download cluster credentials
- Merge them into your `~/.kube/config` file
- Set the current context to your AKS cluster

### Method 2: Specify a Custom kubeconfig File

```bash
# Get credentials into a custom file
az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --file ~/my-kubeconfig.yaml

# Use the custom file
export KUBECONFIG=~/my-kubeconfig.yaml
kubectl get nodes
```

### Method 3: For CI/CD (GitHub Actions)

For GitHub Actions workflows, you can either:

**Option A: Use Azure login (already in workflow)**
- The workflow already has `azure/login@v2` and `azure/aks-set-context@v4` actions
- They automatically configure kubectl

**Option B: Use base64-encoded kubeconfig**

```bash
# Get kubeconfig and base64 encode it
az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --file kubeconfig.yaml

# Encode it
cat kubeconfig.yaml | base64 -w 0

# Add as GitHub secret: KUBE_CONFIG_BASE64
```

## Verify Connection

```bash
# Check current context
kubectl config current-context

# List all contexts
kubectl config get-contexts

# Switch context (if you have multiple clusters)
kubectl config use-context <context-name>

# Test connection
kubectl cluster-info
kubectl get nodes
kubectl get pods --all-namespaces
```

## Common kubectl Commands

```bash
# Get pods
kubectl get pods -n muzika
kubectl get pods --all-namespaces

# Get pods with details
kubectl get pods -n muzika -o wide

# Describe pod (to see why it's pending/failing)
kubectl describe pod <pod-name> -n muzika

# View pod logs
kubectl logs <pod-name> -n muzika
kubectl logs -n muzika -l app=authmanager

# Get events (to debug issues)
kubectl get events -n muzika --sort-by='.lastTimestamp'

# Check resource usage
kubectl top nodes
kubectl top pods -n muzika

# Check deployments
kubectl get deployments -n muzika
kubectl describe deployment authmanager -n muzika

# Check services
kubectl get services -n muzika

# Check secrets
kubectl get secrets -n muzika
kubectl describe secret authmanager-secrets -n muzika

# Check ConfigMaps
kubectl get configmaps -n muzika

# Check namespace
kubectl get namespace muzika
kubectl describe namespace muzika
```

## Troubleshooting kubectl Connection

### Issue: "Unable to connect to the server"

**Solution:**
```bash
# Re-download credentials
az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --overwrite-existing

# Verify Azure login
az account show
```

### Issue: "You must be logged in to the server"

**Solution:**
```bash
# Login to Azure
az login

# Set correct subscription
az account set --subscription <SUBSCRIPTION_ID>

# Get credentials again
az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --overwrite-existing
```

### Issue: Wrong cluster context

**Solution:**
```bash
# List contexts
kubectl config get-contexts

# Switch to correct context
kubectl config use-context <correct-context-name>

# Or delete old context and get new one
kubectl config delete-context <old-context>
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME
```

## Quick Reference

```bash
# One-liner to connect to AKS
az aks get-credentials --resource-group <RG> --name <AKS_NAME> && kubectl get nodes

# Check if you're connected to the right cluster
kubectl config current-context

# Get all namespaces
kubectl get namespaces

# Get all pods across all namespaces
kubectl get pods --all-namespaces

# Watch pods (auto-refresh)
kubectl get pods -n muzika -w

# Delete a pod (will be recreated by deployment)
kubectl delete pod <pod-name> -n muzika

# Restart deployment (rolling restart)
kubectl rollout restart deployment/authmanager -n muzika

# View deployment status
kubectl rollout status deployment/authmanager -n muzika
```

