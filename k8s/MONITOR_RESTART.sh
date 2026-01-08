#!/bin/bash
# Monitor node pool upgrade/restart progress

RESOURCE_GROUP="${RESOURCE_GROUP:-Digeper}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-Digeper-aks}"
NODEPOOL_NAME="${NODEPOOL_NAME:-nodepool1}"

echo "========================================="
echo "  Monitoring Node Pool Restart"
echo "========================================="
echo ""
echo "Press Ctrl+C to stop monitoring"
echo ""

# Get kubectl credentials
az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER_NAME \
    --overwrite-existing > /dev/null 2>&1

# Function to print status
print_status() {
    clear
    echo "========================================="
    echo "  Node Pool & Node Status Monitor"
    echo "========================================="
    echo ""
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Node pool status
    echo "1. Node Pool Status:"
    echo "-------------------"
    PROVISIONING_STATE=$(az aks nodepool show \
        --resource-group $RESOURCE_GROUP \
        --cluster-name $AKS_CLUSTER_NAME \
        --name $NODEPOOL_NAME \
        --query "provisioningState" -o tsv 2>/dev/null || echo "Unknown")
    
    COUNT=$(az aks nodepool show \
        --resource-group $RESOURCE_GROUP \
        --cluster-name $AKS_CLUSTER_NAME \
        --name $NODEPOOL_NAME \
        --query "count" -o tsv 2>/dev/null || echo "0")
    
    echo "Provisioning State: $PROVISIONING_STATE"
    echo "Node Count: $COUNT"
    echo ""
    
    # Node status
    echo "2. Node Status:"
    echo "--------------"
    if kubectl get nodes &> /dev/null; then
        READY_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
        NOT_READY_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " NotReady " || echo "0")
        TOTAL_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
        
        echo "Ready: $READY_COUNT"
        echo "NotReady: $NOT_READY_COUNT"
        echo "Total: $TOTAL_COUNT"
        echo ""
        
        if [ "$TOTAL_COUNT" -gt 0 ]; then
            echo "Node Details:"
            kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[?\(@.type==\"Ready\"\)].status,NETWORK:.status.conditions[?\(@.type==\"NetworkUnavailable\"\)].status,VERSION:.status.nodeInfo.kubeletVersion 2>/dev/null || kubectl get nodes
        else
            echo "No nodes found yet..."
        fi
    else
        echo "Cannot connect to cluster (nodes may be restarting)"
    fi
    echo ""
    
    # CNI pods
    echo "3. CNI Pods Status:"
    echo "------------------"
    if kubectl get pods -n kube-system &> /dev/null; then
        kubectl get pods -n kube-system -l k8s-app=azure-cni -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready,NODE:.spec.nodeName 2>/dev/null | head -5 || echo "No CNI pods found"
    else
        echo "Cannot check pods (cluster may be restarting)"
    fi
    echo ""
    
    # InvalidDiskCapacity errors
    echo "4. InvalidDiskCapacity Errors:"
    echo "-----------------------------"
    if kubectl describe nodes &> /dev/null 2>&1; then
        ERROR_COUNT=$(kubectl describe nodes 2>/dev/null | grep -c "InvalidDiskCapacity" || echo "0")
        if [ "$ERROR_COUNT" -eq 0 ]; then
            echo "✓ No InvalidDiskCapacity errors"
        else
            echo "⚠ Found $ERROR_COUNT InvalidDiskCapacity error(s)"
            echo "Recent errors:"
            kubectl describe nodes 2>/dev/null | grep -B 1 "InvalidDiskCapacity" | tail -4
        fi
    else
        echo "Cannot check (nodes may be restarting)"
    fi
    echo ""
    
    # NetworkReady status
    echo "5. Network Status:"
    echo "-----------------"
    if kubectl get nodes &> /dev/null 2>&1 && [ "$TOTAL_COUNT" -gt 0 ]; then
        NETWORK_READY=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="NetworkUnavailable")].status}' 2>/dev/null || echo "Unknown")
        if [ "$NETWORK_READY" = "False" ]; then
            echo "✓ Network is available"
        elif [ "$NETWORK_READY" = "True" ]; then
            echo "⚠ Network is unavailable"
        else
            echo "Status: $NETWORK_READY"
        fi
    else
        echo "Cannot determine (no nodes or cluster restarting)"
    fi
    echo ""
    
    # Recent events
    echo "6. Recent Events (last 3):"
    echo "-------------------------"
    if kubectl get events --all-namespaces --sort-by='.lastTimestamp' &> /dev/null 2>&1; then
        kubectl get events --all-namespaces --sort-by='.lastTimestamp' 2>/dev/null | tail -3 || echo "No recent events"
    else
        echo "Cannot retrieve events"
    fi
    echo ""
    
    # Progress indicator
    echo "========================================="
    if [ "$PROVISIONING_STATE" = "Succeeded" ] && [ "$READY_COUNT" -eq "$COUNT" ] && [ "$READY_COUNT" -gt 0 ]; then
        echo "✓ Upgrade/Restart Complete!"
        echo "All nodes are Ready"
        return 0
    elif [ "$PROVISIONING_STATE" = "Upgrading" ] || [ "$PROVISIONING_STATE" = "Scaling" ]; then
        echo "⏳ In Progress... ($PROVISIONING_STATE)"
    elif [ "$PROVISIONING_STATE" = "Failed" ]; then
        echo "✗ Upgrade Failed - Check Azure portal"
        return 1
    else
        echo "⏳ Waiting for nodes to become Ready..."
    fi
    echo "========================================="
    echo ""
    echo "Refreshing in 10 seconds... (Ctrl+C to stop)"
}

# Monitor loop
while true; do
    print_status
    EXIT_CODE=$?
    
    # Exit if complete or failed
    if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 1 ]; then
        break
    fi
    
    sleep 10
done

echo ""
echo "Monitoring stopped."

