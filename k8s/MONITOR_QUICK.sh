#!/bin/bash
# Quick one-time status check

RESOURCE_GROUP="${RESOURCE_GROUP:-Digeper}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-Digeper-aks}"

echo "Quick Status Check:"
echo "==================="
echo ""

# Node pool
PROV_STATE=$(az aks nodepool show \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name nodepool1 \
    --query "provisioningState" -o tsv 2>/dev/null || echo "Unknown")
COUNT=$(az aks nodepool show \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name nodepool1 \
    --query "count" -o tsv 2>/dev/null || echo "0")

echo "Node Pool: $PROV_STATE (count: $COUNT)"

# Nodes
if kubectl get nodes &> /dev/null 2>&1; then
    READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
    TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "Nodes: $READY/$TOTAL Ready"
    
    if [ "$READY" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
        echo ""
        echo "✓ All nodes Ready!"
        kubectl get nodes
    fi
else
    echo "Nodes: Cannot connect"
fi

echo ""

