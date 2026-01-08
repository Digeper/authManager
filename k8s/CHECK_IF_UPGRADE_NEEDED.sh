#!/bin/bash
# Check if node pool upgrade is needed and current status

RESOURCE_GROUP="${RESOURCE_GROUP:-digeper}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-digeper-aks}"
NODEPOOL_NAME="${NODEPOOL_NAME:-nodepool1}"

echo "========================================="
echo "  Node Pool Upgrade Status Check"
echo "========================================="
echo ""

# Check if logged in
if ! az account show &> /dev/null; then
    echo "ERROR: Please login to Azure first: az login"
    exit 1
fi

echo "1. Current Node Pool Status:"
az aks nodepool show \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name $NODEPOOL_NAME \
    --query "{provisioningState:provisioningState,powerState:powerState,count:count,orchestratorVersion:orchestratorVersion}" -o table

echo ""
echo "2. Cluster Kubernetes Version:"
CLUSTER_VERSION=$(az aks show \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --query kubernetesVersion -o tsv)
echo "Cluster version: $CLUSTER_VERSION"

NODEPOOL_VERSION=$(az aks nodepool show \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name $NODEPOOL_NAME \
    --query orchestratorVersion -o tsv)
echo "Node pool version: $NODEPOOL_VERSION"

echo ""
if [ "$CLUSTER_VERSION" = "$NODEPOOL_VERSION" ]; then
    echo "⚠ Node pool version matches cluster version"
    echo "  If InvalidDiskCapacity persists, try:"
    echo "  - Updating node pool with --node-vm-size change"
    echo "  - Or creating a new node pool with different configuration"
else
    echo "✓ Node pool version differs from cluster version"
    echo "  This might indicate an upgrade is in progress or needed"
fi

echo ""
echo "3. Node Status (via kubectl):"
if kubectl get nodes &> /dev/null; then
    kubectl get nodes -o wide
    echo ""
    echo "4. InvalidDiskCapacity Errors:"
    INVALID_DISK=$(kubectl describe nodes 2>/dev/null | grep -i "InvalidDiskCapacity" | wc -l || echo "0")
    if [ "$INVALID_DISK" -gt 0 ]; then
        echo "✗ Found $INVALID_DISK InvalidDiskCapacity error(s)"
        echo ""
        echo "Recent errors:"
        kubectl describe nodes 2>/dev/null | grep -B 2 -A 2 "InvalidDiskCapacity" | tail -10
    else
        echo "✓ No InvalidDiskCapacity errors found"
    fi
else
    echo "Could not connect to cluster (kubectl not configured or cluster not accessible)"
fi

echo ""
echo "========================================="
echo "  Recommendation"
echo "========================================="
echo ""

if [ "$INVALID_DISK" -gt 0 ] 2>/dev/null; then
    echo "InvalidDiskCapacity error still present. Try one of these:"
    echo ""
    echo "Option 1: Update node pool VM size (forces refresh):"
    echo "  az aks nodepool update \\"
    echo "    --resource-group $RESOURCE_GROUP \\"
    echo "    --cluster-name $AKS_CLUSTER_NAME \\"
    echo "    --name $NODEPOOL_NAME \\"
    echo "    --node-vm-size Standard_DS3_v2"
    echo ""
    echo "Option 2: Upgrade node pool:"
    echo "  az aks nodepool upgrade \\"
    echo "    --resource-group $RESOURCE_GROUP \\"
    echo "    --cluster-name $AKS_CLUSTER_NAME \\"
    echo "    --name $NODEPOOL_NAME \\"
    echo "    --kubernetes-version $CLUSTER_VERSION"
    echo ""
    echo "Option 3: Create new node pool with different config:"
    echo "  az aks nodepool add \\"
    echo "    --resource-group $RESOURCE_GROUP \\"
    echo "    --cluster-name $AKS_CLUSTER_NAME \\"
    echo "    --name nodepool2 \\"
    echo "    --node-count 1 \\"
    echo "    --node-vm-size Standard_DS3_v2"
else
    echo "No InvalidDiskCapacity errors detected."
    echo "If upgrade was run, wait a few more minutes for nodes to initialize."
fi

