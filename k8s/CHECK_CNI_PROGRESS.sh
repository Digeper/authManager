#!/bin/bash
# Check CNI initialization progress

echo "========================================="
echo "  CNI Initialization Status"
echo "========================================="
echo ""

echo "1. Node Status:"
kubectl get nodes -o wide
echo ""

echo "2. Node Ready Condition:"
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{": "}{range .status.conditions[?(@.type=="Ready")]}{.status} ({.reason}) - {.message}{end}{"\n"}{end}'
echo ""

echo "3. Network Ready Condition:"
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{": "}{range .status.conditions[?(@.type=="NetworkUnavailable")]}{.status} ({.reason}) - {.message}{end}{"\n"}{end}'
echo ""

echo "4. CNI-related Pods:"
echo "Azure CNI pods:"
kubectl get pods -n kube-system | grep -E "azure-cni|azure-cns"
echo ""
echo "Network plugins:"
kubectl get pods -n kube-system | grep -E "network|calico|weave"
echo ""

echo "5. CNI DaemonSet Status:"
kubectl get daemonset -n kube-system -l k8s-app=azure-cni -o wide 2>/dev/null || echo "Azure CNI DaemonSet not found"
echo ""

echo "6. Recent NetworkNotReady Events:"
kubectl get events --all-namespaces --field-selector reason=NetworkNotReady --sort-by='.lastTimestamp' | tail -5
echo ""

echo "7. Node Detailed Conditions:"
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
if [ -n "$NODE_NAME" ]; then
    echo "Node: $NODE_NAME"
    kubectl describe node $NODE_NAME | grep -A 10 "Conditions:"
    echo ""
    
    echo "Recent events with Network/CNI keywords:"
    kubectl describe node $NODE_NAME | grep -i -E "network|cni|ready" | tail -10
fi

echo ""
echo "========================================="
echo "  Recommendations"
echo "========================================="
echo ""

NODE_READY=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
NETWORK_STATUS=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="NetworkUnavailable")].status}' 2>/dev/null || echo "Unknown")

if [ "$NODE_READY" = "True" ]; then
    echo "✓ Node is Ready!"
    if [ "$NETWORK_STATUS" = "False" ]; then
        echo "✓ Network is available!"
        echo "CNI should be working now. Pods should be able to schedule."
    else
        echo "⚠ NetworkUnavailable is $NETWORK_STATUS - this is unusual if node is Ready"
    fi
elif [ "$NODE_READY" = "False" ]; then
    ELAPSED_TIME=$(kubectl get events --field-selector reason=NetworkNotReady --sort-by='.firstTimestamp' -o jsonpath='{.items[0].firstTimestamp}' 2>/dev/null)
    
    echo "✗ Node is NotReady"
    echo ""
    
    if [ -n "$ELAPSED_TIME" ]; then
        echo "First NetworkNotReady event was at: $ELAPSED_TIME"
        echo "If it's been >15 minutes, consider taking action."
    fi
    
    echo ""
    echo "If CNI has been failing for >15 minutes:"
    echo "  1. Check if InvalidDiskCapacity error still exists"
    echo "  2. If yes, try: az aks nodepool upgrade (see WAIT_OR_FIX.md)"
    echo "  3. Or scale to 0 and back up again"
    echo ""
    echo "If InvalidDiskCapacity is gone but CNI still not initializing:"
    echo "  - This may be an Azure platform issue"
    echo "  - Try creating a new node pool with different configuration"
    echo "  - Or contact Azure support"
fi

