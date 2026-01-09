# Pipeline Setup for Key Vault Secrets

## Problem

The SecretProviderClass creates the Kubernetes secret only when a pod mounts the volume. But the application pod can't start without the secret, creating a chicken-and-egg problem.

## Solution: Init Job in Pipeline

Add this step to your CI/CD pipeline **before** deploying the application:

### Step 1: Apply SecretProviderClass

```bash
kubectl apply -f AuthorizationManager/k8s/secretproviderclass-applied.yaml
```

### Step 2: Run Init Job to Trigger Secret Creation

```bash
kubectl apply -f AuthorizationManager/k8s/init-secret-job.yaml
```

Wait for the job to complete:
```bash
kubectl wait --for=condition=complete --timeout=60s job/authmanager-init-secret -n muzika
```

This job mounts the SecretProviderClass volume, which triggers the CSI driver to create the `authmanager-secrets` Kubernetes secret from Key Vault.

### Step 3: Verify Secret Created

```bash
kubectl get secret authmanager-secrets -n muzika
```

### Step 4: Deploy Application

Now deploy your application - the secret will exist and the pod can start:

```bash
kubectl apply -f AuthorizationManager/k8s/deployment.yaml
```

### Step 5: Cleanup Init Job (Optional)

The job auto-deletes after 60 seconds (TTL), but you can delete it manually:

```bash
kubectl delete job authmanager-init-secret -n muzika
```

## Pipeline Script Example

```bash
#!/bin/bash
set -e

# Apply SecretProviderClass
kubectl apply -f AuthorizationManager/k8s/secretproviderclass-applied.yaml

# Run init job to create secret
kubectl apply -f AuthorizationManager/k8s/init-secret-job.yaml

# Wait for secret to be created
echo "Waiting for secret to be created..."
kubectl wait --for=condition=complete --timeout=60s job/authmanager-init-secret -n muzika || true

# Verify secret exists
if kubectl get secret authmanager-secrets -n muzika > /dev/null 2>&1; then
    echo "✓ Secret created successfully"
else
    echo "✗ Secret not created - check SecretProviderClass and Key Vault permissions"
    exit 1
fi

# Deploy application
kubectl apply -f AuthorizationManager/k8s/deployment.yaml

# Cleanup init job
kubectl delete job authmanager-init-secret -n muzika --ignore-not-found=true
```

## Alternative: Use Helm Pre-Hook

If using Helm, you can use a pre-install hook:

```yaml
# In your Helm chart
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "authmanager.fullname" . }}-init-secret
  annotations:
    "helm.sh/hook": pre-install
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
```

## Troubleshooting

If the secret still isn't created:

1. **Check init job logs:**
   ```bash
   kubectl logs job/authmanager-init-secret -n muzika
   ```

2. **Check init job status:**
   ```bash
   kubectl describe job authmanager-init-secret -n muzika
   ```

3. **Verify SecretProviderClass:**
   ```bash
   kubectl describe secretproviderclass authmanager-azure-keyvault -n muzika
   ```

4. **Check Key Vault permissions:**
   - Managed identity needs "Get" and "List" permissions on Key Vault
