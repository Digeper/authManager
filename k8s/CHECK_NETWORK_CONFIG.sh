#!/bin/bash
# Check AKS network configuration for potential issues

RESOURCE_GROUP="${RESOURCE_GROUP:-digeper}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-digeper-aks}"

echo "========================================="
echo "  AKS Network Configuration Check"
echo "========================================="
echo ""

# Check if logged in
if ! az account show &> /dev/null; then
    echo "ERROR: Please login to Azure first: az login"
    exit 1
fi

echo "1. Cluster Network Profile:"
echo "=========================="
az aks show \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --query "networkProfile" -o json

echo ""
echo "2. Network Plugin Type:"
NETWORK_PLUGIN=$(az aks show \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --query "networkProfile.networkPlugin" -o tsv)
echo "Network Plugin: $NETWORK_PLUGIN"

if [ "$NETWORK_PLUGIN" = "azure" ]; then
    echo "✓ Using Azure CNI"
    echo ""
    echo "3. Azure CNI Configuration:"
    az aks show \
        --resource-group $RESOURCE_GROUP \
        --name $AKS_CLUSTER_NAME \
        --query "networkProfile" -o json | grep -E "networkPluginMode|podCidr|serviceCidr|dnsServiceIP"
    
    echo ""
    echo "4. Check Subnet Configuration:"
    VNET_SUBNET_ID=$(az aks show \
        --resource-group $RESOURCE_GROUP \
        --name $AKS_CLUSTER_NAME \
        --query "agentPoolProfiles[0].vnetSubnetId" -o tsv)
    
    if [ -n "$VNET_SUBNET_ID" ]; then
        echo "Subnet ID: $VNET_SUBNET_ID"
        
        # Extract resource group and subnet name from ID
        # Format: /subscriptions/.../resourceGroups/.../providers/Microsoft.Network/virtualNetworks/.../subnets/...
        if [[ $VNET_SUBNET_ID =~ /resourceGroups/([^/]+)/ ]]; then
            VNET_RG="${BASH_REMATCH[1]}"
            echo "VNet Resource Group: $VNET_RG"
        fi
        
        if [[ $VNET_SUBNET_ID =~ /virtualNetworks/([^/]+) ]]; then
            VNET_NAME="${BASH_REMATCH[1]}"
            echo "VNet Name: $VNET_NAME"
        fi
        
        if [[ $VNET_SUBNET_ID =~ /subnets/([^/]+)$ ]]; then
            SUBNET_NAME="${BASH_REMATCH[1]}"
            echo "Subnet Name: $SUBNET_NAME"
        fi
        
        echo ""
        echo "5. Subnet Details:"
        if [ -n "$VNET_RG" ] && [ -n "$VNET_NAME" ] && [ -n "$SUBNET_NAME" ]; then
            az network vnet subnet show \
                --resource-group $VNET_RG \
                --vnet-name $VNET_NAME \
                --name $SUBNET_NAME \
                --query "{addressPrefix:addressPrefix,addressPrefixes:addressPrefixes,ipConfigurations:length(ipConfigurations),delegation:delegations[*].serviceName}" -o json
            
            echo ""
            echo "6. Subnet IP Usage:"
            SUBNET_PREFIX=$(az network vnet subnet show \
                --resource-group $VNET_RG \
                --vnet-name $VNET_NAME \
                --name $SUBNET_NAME \
                --query "addressPrefix" -o tsv)
            
            IP_COUNT=$(az network vnet subnet show \
                --resource-group $VNET_RG \
                --vnet-name $VNET_NAME \
                --name $SUBNET_NAME \
                --query "length(ipConfigurations)" -o tsv)
            
            echo "Subnet: $SUBNET_PREFIX"
            echo "Used IPs: $IP_COUNT"
            echo ""
            echo "⚠ With Azure CNI, you need:"
            echo "  - (Number of nodes × max pods per node) + overhead"
            echo "  - Example: 3 nodes × 30 pods = 90 IPs minimum"
            echo "  - Recommended: At least /24 subnet (256 IPs) for small clusters"
        fi
    else
        echo "⚠ No custom subnet configured - using default"
        echo "  This might be fine if using kubenet, but Azure CNI requires explicit subnet"
    fi
    
elif [ "$NETWORK_PLUGIN" = "kubenet" ]; then
    echo "✓ Using Kubenet (simpler networking)"
    echo ""
    echo "3. Kubenet Configuration:"
    az aks show \
        --resource-group $RESOURCE_GROUP \
        --name $AKS_CLUSTER_NAME \
        --query "networkProfile" -o json | grep -E "podCidr|serviceCidr|dnsServiceIP"
else
    echo "⚠ Unknown network plugin: $NETWORK_PLUGIN"
fi

echo ""
echo "7. Node Pool Network Configuration:"
echo "===================================="
az aks nodepool list \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --query "[].{name:name,maxPods:maxPods,vnetSubnetId:vnetSubnetId,enableNodePublicIP:enableNodePublicIP}" -o table

echo ""
echo "8. Network Security Groups:"
echo "==========================="
if [ -n "$VNET_RG" ] && [ -n "$SUBNET_NAME" ]; then
    NSG_ID=$(az network vnet subnet show \
        --resource-group $VNET_RG \
        --vnet-name $VNET_NAME \
        --name $SUBNET_NAME \
        --query "networkSecurityGroup.id" -o tsv)
    
    if [ -n "$NSG_ID" ]; then
        echo "NSG attached to subnet: Yes"
        echo "Check for rules blocking required ports:"
        echo "  - Port 443 (HTTPS)"
        echo "  - Port 10250 (Kubelet)"
        echo "  - Port 10255 (Read-only Kubelet)"
        echo "  - Port 53 (DNS)"
        echo "  - ICMP"
    else
        echo "NSG attached: No (or using default)"
    fi
fi

echo ""
echo "========================================="
echo "  Common Network Issues to Check"
echo "========================================="
echo ""
echo "1. Subnet IP Exhaustion (Azure CNI):"
echo "   - If subnet is too small, pods can't get IPs"
echo "   - CNI fails to initialize → InvalidDiskCapacity errors"
echo "   - Fix: Use larger subnet or switch to kubenet"
echo ""
echo "2. Missing Subnet Delegation (Azure CNI):"
echo "   - Subnet must be delegated to Microsoft.ContainerService/managedClusters"
echo "   - Check: az network vnet subnet show --query delegations"
echo ""
echo "3. NSG Blocking Required Ports:"
echo "   - Kubelet, DNS, and other services need network access"
echo "   - Check NSG rules on subnet"
echo ""
echo "4. Service Principal Permissions:"
echo "   - Service principal needs Contributor role on VNet"
echo "   - Check: az role assignment list --scope <vnet-id>"
echo ""

