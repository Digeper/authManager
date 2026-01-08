#!/bin/bash
# Fix missing subnet delegation - this is likely causing CNI initialization failure

set -e

RESOURCE_GROUP="${RESOURCE_GROUP:-digeper}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-digeper-aks}"

# Build managed resource group name
RG_UPPER=$(echo "$RESOURCE_GROUP" | awk '{print toupper($0)}')
AKS_UPPER=$(echo "$AKS_CLUSTER_NAME" | awk '{print toupper($0)}')
MC_RG="MC_${RG_UPPER}_${AKS_UPPER}_italynorth"

echo "========================================="
echo "  Fix Subnet Delegation"
echo "========================================="
echo ""

# Check if logged in
if ! az account show &> /dev/null; then
    echo "ERROR: Please login to Azure first: az login"
    exit 1
fi

echo "1. Finding subnet in managed resource group..."
VNET_NAME=$(az network vnet list \
    --resource-group $MC_RG \
    --query "[0].name" -o tsv 2>/dev/null || echo "")

if [ -z "$VNET_NAME" ]; then
    echo "ERROR: Could not find VNet in managed resource group: $MC_RG"
    exit 1
fi

echo "VNet: $VNET_NAME"
echo ""

SUBNET_NAME=$(az network vnet subnet list \
    --resource-group $MC_RG \
    --vnet-name $VNET_NAME \
    --query "[0].name" -o tsv)

if [ -z "$SUBNET_NAME" ]; then
    echo "ERROR: Could not find subnet"
    exit 1
fi

echo "2. Current subnet delegation status..."
DELEGATIONS=$(az network vnet subnet show \
    --resource-group $MC_RG \
    --vnet-name $VNET_NAME \
    --name $SUBNET_NAME \
    --query "delegations" -o json 2>/dev/null || echo "[]")

echo "Current delegations: $DELEGATIONS"
echo ""

# Check if delegation already exists
if echo "$DELEGATIONS" | grep -q "Microsoft.ContainerService/managedClusters"; then
    echo "✓ Delegation already exists!"
    exit 0
fi

echo "3. Adding subnet delegation to Microsoft.ContainerService/managedClusters..."
echo ""

az network vnet subnet update \
    --resource-group $MC_RG \
    --vnet-name $VNET_NAME \
    --name $SUBNET_NAME \
    --delegations Microsoft.ContainerService/managedClusters

echo ""
echo "✓ Delegation added successfully!"
echo ""

echo "4. Verifying delegation..."
NEW_DELEGATIONS=$(az network vnet subnet show \
    --resource-group $MC_RG \
    --vnet-name $VNET_NAME \
    --name $SUBNET_NAME \
    --query "delegations" -o json)

echo "New delegations: $NEW_DELEGATIONS"
echo ""

echo "========================================="
echo "  Next Steps"
echo "========================================="
echo ""
echo "1. Restart the node pool to apply the change:"
echo "   az aks nodepool scale \\"
echo "     --resource-group $RESOURCE_GROUP \\"
echo "     --cluster-name $AKS_CLUSTER_NAME \\"
echo "     --name nodepool1 \\"
echo "     --node-count 0"
echo ""
echo "   # Wait 2-3 minutes, then:"
echo "   az aks nodepool scale \\"
echo "     --resource-group $RESOURCE_GROUP \\"
echo "     --cluster-name $AKS_CLUSTER_NAME \\"
echo "     --name nodepool1 \\"
echo "     --node-count 1"
echo ""
echo "2. Wait for nodes to become Ready (5-10 minutes)"
echo "3. CNI should now initialize properly!"

