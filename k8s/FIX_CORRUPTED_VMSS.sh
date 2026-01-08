#!/bin/bash
# Fix corrupted VMSS image by upgrading node pool
# This forces Azure to use a fresh VMSS image

set -e

RESOURCE_GROUP="${RESOURCE_GROUP:-digeper}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-digeper-aks}"
NODEPOOL_NAME="${NODEPOOL_NAME:-nodepool1}"

echo "========================================="
echo "  Fix Corrupted VMSS Image"
echo "========================================="
echo ""
echo "This script will upgrade the node pool to get a fresh VMSS image."
echo "The InvalidDiskCapacity error has persisted for 57+ minutes,"
echo "indicating the VMSS base image is corrupted."
echo ""
echo "Resource Group: $RESOURCE_GROUP"
echo "AKS Cluster: $AKS_CLUSTER_NAME"
echo "Node Pool: $NODEPOOL_NAME"
echo ""

# Check if logged in
if ! az account show &> /dev/null; then
    echo "ERROR: Please login to Azure first: az login"
    exit 1
fi

echo "Step 1: Getting current Kubernetes version..."
K8S_VERSION=$(az aks show \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --query kubernetesVersion -o tsv)

if [ -z "$K8S_VERSION" ]; then
    echo "ERROR: Could not get Kubernetes version"
    exit 1
fi

echo "Current K8s version: $K8S_VERSION"
echo ""

echo "Step 2: Checking current node pool status..."
CURRENT_COUNT=$(az aks nodepool show \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name $NODEPOOL_NAME \
    --query "count" -o tsv)

echo "Current node count: $CURRENT_COUNT"
echo ""

echo "Step 3: Upgrading node pool to force fresh VMSS image..."
echo "This will replace all nodes with fresh VMs from a new VMSS image."
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

az aks nodepool upgrade \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name $NODEPOOL_NAME \
    --kubernetes-version $K8S_VERSION \
    --no-wait

echo ""
echo "Upgrade initiated. This will take 10-15 minutes."
echo ""

echo "Step 4: Monitoring upgrade progress..."
echo ""

# Monitor upgrade
MAX_WAIT=900  # 15 minutes
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    PROVISIONING_STATE=$(az aks nodepool show \
        --resource-group $RESOURCE_GROUP \
        --cluster-name $AKS_CLUSTER_NAME \
        --name $NODEPOOL_NAME \
        --query "provisioningState" -o tsv 2>/dev/null || echo "unknown")
    
    echo "[${ELAPSED}s] Provisioning state: $PROVISIONING_STATE"
    
    if [ "$PROVISIONING_STATE" = "Succeeded" ]; then
        echo ""
        echo "✓ Upgrade completed successfully!"
        break
    elif [ "$PROVISIONING_STATE" = "Failed" ]; then
        echo ""
        echo "✗ Upgrade failed. Check Azure portal or run:"
        echo "  az aks nodepool show --resource-group $RESOURCE_GROUP --cluster-name $AKS_CLUSTER_NAME --name $NODEPOOL_NAME"
        exit 1
    fi
    
    sleep 30
    ELAPSED=$((ELAPSED + 30))
done

if [ "$PROVISIONING_STATE" != "Succeeded" ]; then
    echo ""
    echo "Upgrade is taking longer than expected. Check status manually:"
    echo "  az aks nodepool show --resource-group $RESOURCE_GROUP --cluster-name $AKS_CLUSTER_NAME --name $NODEPOOL_NAME"
    exit 0
fi

echo ""
echo "Step 5: Getting kubectl credentials and checking nodes..."
az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --overwrite-existing

echo ""
echo "Waiting for nodes to become Ready (up to 10 minutes)..."
MAX_NODE_WAIT=600
NODE_ELAPSED=0

while [ $NODE_ELAPSED -lt $MAX_NODE_WAIT ]; do
    READY_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
    TOTAL_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$TOTAL_COUNT" -gt 0 ] && [ "$READY_COUNT" -eq "$TOTAL_COUNT" ]; then
        echo ""
        echo "✓ All $TOTAL_COUNT nodes are Ready!"
        break
    fi
    
    echo "  Ready nodes: $READY_COUNT/$TOTAL_COUNT (elapsed: ${NODE_ELAPSED}s)"
    sleep 15
    NODE_ELAPSED=$((NODE_ELAPSED + 15))
done

echo ""
echo "Final node status:"
kubectl get nodes -o wide

echo ""
echo "Checking for InvalidDiskCapacity errors..."
kubectl describe nodes | grep -i "InvalidDiskCapacity" || echo "✓ No InvalidDiskCapacity errors found!"

echo ""
echo "========================================="
echo "  VMSS Image Refresh Complete!"
echo "========================================="
echo ""
echo "If nodes are Ready and no InvalidDiskCapacity errors:"
echo "  - System pods should start automatically"
echo "  - Your AuthorizationManager pods can now be deployed"

