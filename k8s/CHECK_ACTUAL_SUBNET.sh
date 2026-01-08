#!/bin/bash
# Check what subnet is actually being used by the nodes

RESOURCE_GROUP="${RESOURCE_GROUP:-digeper}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-digeper-aks}"

# Build managed resource group name (handle case conversion)
RG_UPPER=$(echo "$RESOURCE_GROUP" | awk '{print toupper($0)}')
AKS_UPPER=$(echo "$AKS_CLUSTER_NAME" | awk '{print toupper($0)}')
MC_RG="MC_${RG_UPPER}_${AKS_UPPER}_italynorth"

echo "========================================="
echo "  Actual Subnet Configuration"
echo "========================================="
echo ""

# Check if logged in
if ! az account show &> /dev/null; then
    echo "ERROR: Please login to Azure first: az login"
    exit 1
fi

echo "1. Finding the actual VNet and Subnet:"
echo "======================================"

# Get the managed resource group (MC_*)
echo "Managed resource group: $MC_RG"
echo ""

# Find VNet in managed resource group
VNET_NAME=$(az network vnet list \
    --resource-group $MC_RG \
    --query "[0].name" -o tsv 2>/dev/null || echo "")

if [ -n "$VNET_NAME" ]; then
    echo "VNet in managed RG: $VNET_NAME"
    echo ""
    
    echo "2. Subnets in VNet:"
    az network vnet subnet list \
        --resource-group $MC_RG \
        --vnet-name $VNET_NAME \
        --query "[].{name:name,addressPrefix:addressPrefix,delegations:delegations[*].serviceName,ipConfigurations:length(ipConfigurations)}" -o table
    
    echo ""
    echo "3. Check Subnet Delegation:"
    SUBNET_NAME=$(az network vnet subnet list \
        --resource-group $MC_RG \
        --vnet-name $VNET_NAME \
        --query "[0].name" -o tsv)
    
    if [ -n "$SUBNET_NAME" ]; then
        echo "First subnet: $SUBNET_NAME"
        DELEGATIONS=$(az network vnet subnet show \
            --resource-group $MC_RG \
            --vnet-name $VNET_NAME \
            --name $SUBNET_NAME \
            --query "delegations" -o json 2>/dev/null || echo "[]")
        
        echo "$DELEGATIONS"
        
        if [ "$DELEGATIONS" = "[]" ] || [ -z "$DELEGATIONS" ]; then
            echo ""
            echo "⚠⚠⚠ PROBLEM FOUND: Subnet is NOT delegated!"
            echo "This prevents CNI from initializing properly."
            echo "Delegation should be: Microsoft.ContainerService/managedClusters"
        else
            echo ""
            echo "✓ Subnet has delegations"
        fi
        
        echo ""
        echo "4. Subnet Details:"
        az network vnet subnet show \
            --resource-group $MC_RG \
            --vnet-name $VNET_NAME \
            --name $SUBNET_NAME \
            --query "{addressPrefix:addressPrefix,ipConfigurations:length(ipConfigurations),networkSecurityGroup:networkSecurityGroup.id}" -o json
        
        echo ""
        echo "5. Node Pool Subnet Reference:"
        NODEPOOL_SUBNET=$(az aks nodepool show \
            --resource-group $RESOURCE_GROUP \
            --cluster-name $AKS_CLUSTER_NAME \
            --name nodepool1 \
            --query "vnetSubnetId" -o tsv 2>/dev/null || echo "null")
        
        if [ "$NODEPOOL_SUBNET" != "null" ] && [ -n "$NODEPOOL_SUBNET" ]; then
            echo "Node pool subnet ID: $NODEPOOL_SUBNET"
        else
            echo "⚠ Node pool has no explicit subnet ID - using default"
        fi
    fi
else
    echo "⚠ Could not find VNet in managed resource group: $MC_RG"
    echo ""
    echo "Trying to find VNet in main resource group..."
    VNET_NAME=$(az network vnet list \
        --resource-group $RESOURCE_GROUP \
        --query "[0].name" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$VNET_NAME" ]; then
        echo "Found VNet: $VNET_NAME in $RESOURCE_GROUP"
        az network vnet subnet list \
            --resource-group $RESOURCE_GROUP \
            --vnet-name $VNET_NAME \
            --query "[].{name:name,addressPrefix:addressPrefix}" -o table
    fi
fi

echo ""
echo "6. Overlay Mode Notes:"
echo "====================="
echo "You're using Azure CNI with overlay mode."
echo "This means:"
echo "  ✓ Pods don't need IPs from the subnet (they use overlay networking)"
echo "  ✓ Node subnet still needs to be properly configured"
echo "  ✓ Nodes themselves need IPs from the subnet"
echo ""
echo "Even in overlay mode, you still need:"
echo "  - Subnet delegated to Microsoft.ContainerService/managedClusters"
echo "  - Enough IPs in subnet for nodes (not pods)"
echo "  - Proper NSG rules"
echo ""

