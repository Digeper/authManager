#!/bin/bash
# Fix Key Vault name placeholder in SecretProviderClass

set -e

KEYVAULT_NAME="${1}"
SECRET_FILE="${2:-AuthorizationManager/k8s/secret.yaml}"

if [ -z "$KEYVAULT_NAME" ]; then
    echo "Usage: $0 <KEYVAULT_NAME> [secret.yaml path]"
    echo ""
    echo "Example:"
    echo "  $0 my-keyvault"
    echo "  $0 my-keyvault AuthorizationManager/k8s/secret.yaml"
    echo ""
    echo "Or set KEYVAULT_NAME environment variable:"
    echo "  KEYVAULT_NAME=my-keyvault $0"
    exit 1
fi

echo "========================================="
echo "  Fix Key Vault Name in SecretProviderClass"
echo "========================================="
echo ""

if [ ! -f "$SECRET_FILE" ]; then
    echo "ERROR: File not found: $SECRET_FILE"
    exit 1
fi

echo "Key Vault Name: $KEYVAULT_NAME"
echo "File: $SECRET_FILE"
echo ""

# Validate Key Vault name format
if ! echo "$KEYVAULT_NAME" | grep -qE '^[-a-zA-Z0-9]{3,24}$'; then
    echo "ERROR: Invalid Key Vault name format!"
    echo "Must match: ^[-a-zA-Z0-9]{3,24}$"
    echo "Your value: $KEYVAULT_NAME"
    exit 1
fi

# Check if placeholder exists
if ! grep -q '\${KEYVAULT_NAME}' "$SECRET_FILE"; then
    echo "⚠ No \${KEYVAULT_NAME} placeholder found in file"
    echo "Current keyvaultName value:"
    grep -A 1 "keyvaultName:" "$SECRET_FILE" | head -2
    echo ""
    read -p "Replace existing value? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
    
    # Replace existing keyvaultName value
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/keyvaultName:.*/keyvaultName: \"$KEYVAULT_NAME\"/" "$SECRET_FILE"
    else
        # Linux
        sed -i "s/keyvaultName:.*/keyvaultName: \"$KEYVAULT_NAME\"/" "$SECRET_FILE"
    fi
else
    # Replace placeholder
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/\${KEYVAULT_NAME}/$KEYVAULT_NAME/g" "$SECRET_FILE"
    else
        # Linux
        sed -i "s/\${KEYVAULT_NAME}/$KEYVAULT_NAME/g" "$SECRET_FILE"
    fi
fi

echo "✓ Key Vault name updated in $SECRET_FILE"
echo ""

echo "Verification:"
grep -A 1 "keyvaultName:" "$SECRET_FILE" | head -2

echo ""
echo "========================================="
echo "  Next Steps"
echo "========================================="
echo ""
echo "1. Apply the updated SecretProviderClass:"
echo "   kubectl apply -f $SECRET_FILE"
echo ""
echo "2. Or apply all manifests:"
echo "   kubectl apply -k AuthorizationManager/k8s/"
echo ""
echo "3. Delete pods to restart them with new config:"
echo "   kubectl delete pods -n muzika -l app=authmanager"
echo ""

