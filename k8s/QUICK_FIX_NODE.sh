#!/bin/bash
# Quick fix script to replace corrupted nodes by scaling node pool to 0 and back up

set -e

RESOURCE_GROUP="${RESOURCE_GROUP:-digeper}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-digeper-aks}"
NODEPOOL_NAME="${NODEPOOL_NAME:-nodepool1}"
TARGET_NODE_COUNT="${TARGET_NODE_COUNT:-3}"

echo "========================================="
echo "  Fix Node Issues - Scale to 0 and Back"
echo "========================================="
echo ""
echo "Resource Group: $RESOURCE_GROUP"
echo "AKS Cluster: $AKS_CLUSTER_NAME"
echo "Node Pool: $NODEPOOL_NAME"
echo "Target Node Count: $TARGET_NODE_COUNT"
echo ""

# Check if logged in
if ! az account show &> /dev/null; then
    echo "Please login to Azure first: az login"
    exit 1
fi

echo "Step 1: Scaling node pool to 0 (will delete all nodes)..."
az aks nodepool scale \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name $NODEPOOL_NAME \
    --node-count 0

echo ""
echo "Step 2: Waiting for nodes to be deleted (checking every 10 seconds)..."
while true; do
    CURRENT_COUNT=$(az aks nodepool show \
        --resource-group $RESOURCE_GROUP \
        --cluster-name $AKS_CLUSTER_NAME \
        --name $NODEPOOL_NAME \
        --query "count" -o tsv 2>/dev/null || echo "1")
    
    if [ "$CURRENT_COUNT" = "0" ] || [ "$CURRENT_COUNT" = "null" ]; then
        echo "All nodes deleted. Proceeding..."
        break
    fi
    echo "  Current node count: $CURRENT_COUNT (waiting for 0)..."
    sleep 10
done

echo ""
echo "Step 3: Scaling back up to $TARGET_NODE_COUNT nodes (creating fresh nodes)..."
az aks nodepool scale \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name $NODEPOOL_NAME \
    --node-count $TARGET_NODE_COUNT

echo ""
echo "Step 4: Waiting for nodes to become Ready (this takes 5-10 minutes)..."
echo "Monitoring node status..."

# Get kubectl credentials
echo "Getting kubectl credentials..."
az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --overwrite-existing

# Wait for nodes to be Ready
MAX_WAIT=600  # 10 minutes
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
    TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$READY_NODES" = "$TARGET_NODE_COUNT" ] && [ "$TOTAL_NODES" = "$TARGET_NODE_COUNT" ]; then
        echo ""
        echo "✓ All $TARGET_NODE_COUNT nodes are Ready!"
        break
    fi
    
    echo "  Ready nodes: $READY_NODES/$TARGET_NODE_COUNT (elapsed: ${ELAPSED}s)"
    sleep 15
    ELAPSED=$((ELAPSED + 15))
done

echo ""
echo "Final node status:"
kubectl get nodes -o wide

echo ""
echo "Checking system pods..."
kubectl get pods -n kube-system

echo ""
echo "========================================="
echo "  Node Replacement Complete!"
echo "========================================="
echo ""
echo "If nodes are Ready, system pods should start automatically."
echo "Then you can deploy your AuthorizationManager pods."

