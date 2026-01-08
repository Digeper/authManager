#!/bin/bash
# Script to check node status and diagnose NotReady issues

echo "========================================="
echo "  Node Status Diagnostic"
echo "========================================="
echo ""

echo "1. Node Status:"
kubectl get nodes -o wide
echo ""

echo "2. Node Conditions:"
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .status.conditions[*]}{.type}={.status} ({.reason}){"\n"}{end}{"\n"}{end}'
echo ""

echo "3. Node Taints:"
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{.spec.taints[*]}{"\n"}{end}'
echo ""

echo "4. Recent Node Events:"
kubectl get events --field-selector involvedObject.kind=Node --sort-by='.lastTimestamp' | tail -20
echo ""

echo "5. Detailed Node Info (first node):"
FIRST_NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
if [ -n "$FIRST_NODE" ]; then
    echo "Node: $FIRST_NODE"
    kubectl describe node $FIRST_NODE | grep -A 20 "Conditions:"
    echo ""
    echo "Recent events for $FIRST_NODE:"
    kubectl describe node $FIRST_NODE | grep -A 10 "Events:"
fi

echo ""
echo "========================================="
echo "  Pod Scheduling Status"
echo "========================================="
echo ""

echo "Pending pods:"
kubectl get pods --all-namespaces --field-selector=status.phase=Pending -o wide
echo ""

echo "System pods in kube-system:"
kubectl get pods -n kube-system | grep -E "Pending|ContainerCreating"
echo ""

echo "========================================="
echo "  Recommendations"
echo "========================================="
echo ""

NODE_STATUS=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

if [ "$NODE_STATUS" = "True" ]; then
    echo "✓ Node is Ready - pods should be able to schedule"
    echo ""
    echo "If pods are still pending, check:"
    echo "  - Resource requests: kubectl describe pod <pod-name>"
    echo "  - Taints/tolerations: kubectl describe node"
elif [ "$NODE_STATUS" = "False" ]; then
    echo "✗ Node is NotReady - this is why pods can't schedule"
    echo ""
    echo "Check why node is NotReady:"
    echo "  kubectl describe node $(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
    echo ""
    echo "Common issues:"
    echo "  - CNI plugin not initialized (NetworkNotReady)"
    echo "  - Disk/filesystem issues (DiskPressure or InvalidDiskCapacity)"
    echo "  - Container runtime issues (ContainerdStart)"
    echo ""
    echo "If node was recently created, wait 5-10 minutes for initialization."
    echo "If it's been >15 minutes, the node may be corrupted - consider scaling to 0 and back up."
else
    echo "? Could not determine node status"
fi

