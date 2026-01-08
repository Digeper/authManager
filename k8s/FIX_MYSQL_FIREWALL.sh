#!/bin/bash
# Fix Azure MySQL firewall to allow AKS connections

set -e

MYSQL_SERVER_NAME="${1:-digeper-mysql-server}"
RESOURCE_GROUP="${RESOURCE_GROUP:-Digeper}"

echo "========================================="
echo "  Fix Azure MySQL Firewall"
echo "========================================="
echo ""

# Check if logged in
if ! az account show &> /dev/null; then
    echo "ERROR: Please login to Azure first: az login"
    exit 1
fi

echo "MySQL Server: $MYSQL_SERVER_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo ""

echo "1. Getting AKS outbound IPs..."
echo "=============================="

AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-Digeper-aks}"
OUTBOUND_IPS=$(az aks show \
    --resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER_NAME \
    --query "networkProfile.loadBalancerProfile.effectiveOutboundIPs[].id" -o tsv 2>/dev/null || echo "")

if [ -n "$OUTBOUND_IPS" ]; then
    echo "AKS outbound IPs:"
    for IP_ID in $OUTBOUND_IPS; do
        IP=$(az network public-ip show --ids "$IP_ID" --query "ipAddress" -o tsv 2>/dev/null || echo "")
        if [ -n "$IP" ]; then
            echo "  - $IP"
        fi
    done
else
    echo "⚠ Could not get outbound IPs automatically"
    echo "You may need to add them manually"
fi

echo ""
echo "2. Current MySQL firewall rules..."
echo "=================================="

az mysql flexible-server firewall-rule list \
    --resource-group $RESOURCE_GROUP \
    --name $MYSQL_SERVER_NAME \
    --query "[].{name:name,startIpAddress:startIpAddress,endIpAddress:endIpAddress}" -o table 2>/dev/null || {
    echo "⚠ Could not list firewall rules"
    echo "Server might not exist or you don't have permissions"
}

echo ""
echo "3. Options to fix:"
echo "=================="
echo ""
echo "Option A: Allow Azure services (recommended for testing)"
echo "  This allows all Azure services to connect"
echo ""
echo "Option B: Add specific AKS outbound IPs"
echo "  More secure, but requires knowing the IPs"
echo ""
echo "Option C: Allow all IPs (0.0.0.0 - 255.255.255.255)"
echo "  Least secure, only for testing"
echo ""

read -p "Choose option (A/B/C) [default: A]: " OPTION
OPTION=${OPTION:-A}

case $OPTION in
    A|a)
        echo ""
        echo "Allowing Azure services to connect..."
        # Azure services use 0.0.0.0 as start and end IP
        az mysql flexible-server firewall-rule create \
            --resource-group $RESOURCE_GROUP \
            --name $MYSQL_SERVER_NAME \
            --rule-name AllowAzureServices \
            --start-ip-address 0.0.0.0 \
            --end-ip-address 0.0.0.0 \
            --output none 2>/dev/null || echo "Rule might already exist"
        
        echo "✓ Firewall rule created (or already exists)"
        ;;
    B|b)
        if [ -z "$OUTBOUND_IPS" ]; then
            echo ""
            echo "Could not get outbound IPs automatically."
            read -p "Enter AKS outbound IP address: " MANUAL_IP
            OUTBOUND_IPS="$MANUAL_IP"
        fi
        
        echo ""
        echo "Adding firewall rules for AKS outbound IPs..."
        for IP_ID in $OUTBOUND_IPS; do
            IP=$(az network public-ip show --ids "$IP_ID" --query "ipAddress" -o tsv 2>/dev/null || echo "")
            if [ -n "$IP" ]; then
                echo "Adding rule for IP: $IP"
                az mysql flexible-server firewall-rule create \
                    --resource-group $RESOURCE_GROUP \
                    --name $MYSQL_SERVER_NAME \
                    --rule-name "AKS-Outbound-${IP//./-}" \
                    --start-ip-address "$IP" \
                    --end-ip-address "$IP" \
                    --output none 2>/dev/null || echo "Rule might already exist"
            fi
        done
        
        echo "✓ Firewall rules added"
        ;;
    C|c)
        echo ""
        echo "WARNING: This allows connections from ANY IP address!"
        read -p "Are you sure? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            az mysql flexible-server firewall-rule create \
                --resource-group $RESOURCE_GROUP \
                --name $MYSQL_SERVER_NAME \
                --rule-name AllowAllIPs \
                --start-ip-address 0.0.0.0 \
                --end-ip-address 255.255.255.255 \
                --output none 2>/dev/null || echo "Rule might already exist"
            
            echo "✓ Firewall rule created (ALLOW ALL - INSECURE!)"
        else
            echo "Cancelled."
        fi
        ;;
esac

echo ""
echo "4. Verifying firewall rules..."
echo "=============================="
az mysql flexible-server firewall-rule list \
    --resource-group $RESOURCE_GROUP \
    --name $MYSQL_SERVER_NAME \
    --query "[].{name:name,startIpAddress:startIpAddress,endIpAddress:endIpAddress}" -o table

echo ""
echo "========================================="
echo "  Next Steps"
echo "========================================="
echo ""
echo "After adding firewall rules, restart pods:"
echo "  kubectl delete pods -n muzika -l app=authmanager"
echo ""
echo "Monitor connection:"
echo "  kubectl logs -n muzika -l app=authmanager -f"
echo ""
echo "If still timing out, check:"
echo "  1. MySQL server is running: az mysql flexible-server show --resource-group $RESOURCE_GROUP --name $MYSQL_SERVER_NAME"
echo "  2. MySQL is in same region/VNet as AKS (if using private endpoint)"
echo "  3. Network security groups aren't blocking port 3306"

