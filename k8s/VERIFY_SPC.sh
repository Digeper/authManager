#!/bin/bash
# Verify SecretProviderClass configuration

echo "Verifying SecretProviderClass Configuration"
echo "==========================================="
echo ""

kubectl get secretproviderclass authmanager-azure-keyvault -n muzika -o yaml | grep -A 10 "parameters:" | head -15

echo ""
echo "Checking specific values:"
echo "------------------------"

TENANT_ID=$(kubectl get secretproviderclass authmanager-azure-keyvault -n muzika -o jsonpath='{.spec.parameters.tenantId}')
USER_ID=$(kubectl get secretproviderclass authmanager-azure-keyvault -n muzika -o jsonpath='{.spec.parameters.userAssignedIdentityID}')
KV_NAME=$(kubectl get secretproviderclass authmanager-azure-keyvault -n muzika -o jsonpath='{.spec.parameters.keyvaultName}')

echo "Tenant ID: $TENANT_ID"
echo "User Assigned Identity ID: '${USER_ID:-<empty>}'"
echo "Key Vault Name: $KV_NAME"
echo ""

# Check if userAssignedIdentityID is actually empty (not a placeholder)
if [ -z "$USER_ID" ] || [ "$USER_ID" = "" ]; then
    echo "✓ userAssignedIdentityID is empty (correct for system-assigned identity)"
elif [ "$USER_ID" = "\${MANAGED_IDENTITY_CLIENT_ID}" ] || [ "$USER_ID" = "'(empty)'" ]; then
    echo "✗ userAssignedIdentityID still has placeholder or invalid value"
    echo "  Current value: '$USER_ID'"
    echo "  Should be: empty string"
else
    echo "✓ userAssignedIdentityID has a value: $USER_ID (user-assigned identity)"
fi

echo ""
echo "Checking for placeholders:"
if kubectl get secretproviderclass authmanager-azure-keyvault -n muzika -o yaml | grep -q '\${'; then
    echo "✗ Found placeholders in SecretProviderClass:"
    kubectl get secretproviderclass authmanager-azure-keyvault -n muzika -o yaml | grep '\${'
else
    echo "✓ No placeholders found"
fi

