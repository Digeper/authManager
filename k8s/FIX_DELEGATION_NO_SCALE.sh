#!/bin/bash
# Fix subnet delegation and restart nodes without scaling to 0

set -e

RESOURCE_GROUP="${RESOURCE_GROUP:-Digeper}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-Digeper-aks}"

# Build managed resource group name (note: Azure uses original case)
RG_UPPER=$(echo "$RESOURCE_GROUP" | awk '{print toupper($0)}')
AKS_UPPER=$(echo "$AKS_CLUSTER_NAME" | awk '{print toupper($0)}')
MC_RG="MC_${RG_UPPER}_${AKS_UPPER}_italynorth"

echo "========================================="
echo "  Fix Subnet Delegation (No Scale)"
echo "========================================="
echo ""

# Check if logged in
if ! az account show &> /dev/null; then
    echo "ERROR: Please login to Azure first: az login"
    exit 1
fi

echo "1. Finding subnet and adding delegation..."
VNET_NAME=$(az network vnet list \
    --resource-group $MC_RG \
    --query "[0].name" -o tsv 2>/dev/null || echo "")

if [ -z "$VNET_NAME" ]; then
    echo "ERROR: Could not find VNet in managed resource group: $MC_RG"
    exit 1
fi

SUBNET_NAME=$(az network vnet subnet list \
    --resource-group $MC_RG \
    --vnet-name $VNET_NAME \
    --query "[0].name" -o tsv)

echo "VNet: $VNET_NAME"
echo "Subnet: $SUBNET_NAME"
echo ""

echo "2. Adding subnet delegation..."
az network vnet subnet update \
    --resource-group $MC_RG \
    --vnet-name $VNET_NAME \
    --name $SUBNET_NAME \
    --delegations Microsoft.ContainerService/managedClusters

echo ""
echo "✓ Delegation added!"
echo ""

echo "3. Checking node pool type..."
NODEPOOL_TYPE=$(az aks nodepool show \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --name nodepool1 \
    --query "type" -o tsv 2>/dev/null || echo "VirtualMachineScaleSets")

echo "Node pool type: $NODEPOOL_TYPE"
echo ""

echo "4. Getting node names to restart..."
az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --overwrite-existing

NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

if [ -z "$NODES" ]; then
    echo "⚠ No nodes found. They may need to be created first."
    echo ""
    echo "After nodes are created, they will use the new delegation."
    exit 0
fi

echo "Found nodes: $NODES"
echo ""

echo "========================================="
echo "  Restart Options"
echo "========================================="
echo ""
echo "Option 1: Delete pods to force node restart (Recommended)"
echo "  This will cause pods to be rescheduled and nodes to restart"
echo ""
echo "Option 2: Upgrade node pool (forces node replacement)"
echo "  This will replace all nodes with fresh ones using new delegation"
echo ""
echo "Option 3: Wait for next auto-update/reboot"
echo "  Nodes will pick up the delegation on next restart"
echo ""

read -p "Choose option (1/2/3) [default: 2]: " OPTION
OPTION=${OPTION:-2}

case $OPTION in
    1)
        echo ""
        echo "Deleting system pods to trigger node restart..."
        # Delete CNI and system pods - they'll be recreated with new config
        kubectl delete pods -n kube-system -l k8s-app=azure-cni 2>/dev/null || true
        kubectl delete pods -n kube-system -l app=secrets-store-csi-driver 2>/dev/null || true
        echo "✓ System pods deleted. They will restart with new delegation."
        ;;
    2)
        echo ""
        echo "Upgrading node pool to force node replacement..."
        K8S_VERSION=$(az aks show \
            --resource-group $RESOURCE_GROUP \
            --cluster-name $AKS_CLUSTER_NAME \
            --query kubernetesVersion -o tsv)
        
        echo "Upgrading to version: $K8S_VERSION"
        az aks nodepool upgrade \
            --resource-group $RESOURCE_GROUP \
            --cluster-name $AKS_CLUSTER_NAME \
            --name nodepool1 \
            --kubernetes-version $K8S_VERSION \
            --no-wait
        
        echo "✓ Upgrade started. This will replace all nodes (10-15 minutes)."
        ;;
    3)
        echo ""
        echo "Delegation is now set. Nodes will use it on next restart."
        echo "You can manually restart nodes later if needed."
        ;;
esac

echo ""
echo "========================================="
echo "  Monitoring"
echo "========================================="
echo ""
echo "Monitor node status:"
echo "  kubectl get nodes -w"
echo ""
echo "Check for CNI initialization:"
echo "  kubectl get pods -n kube-system | grep -E 'azure-cni|cns'"
echo ""
echo "Once nodes are Ready, CNI should work properly!"

