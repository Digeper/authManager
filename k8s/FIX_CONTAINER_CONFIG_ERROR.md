# Fix CreateContainerConfigError

The pod is in `CreateContainerConfigError` which means it can't start because the secret `authmanager-secrets` doesn't exist.

## The Problem

The SecretProviderClass creates the secret when a pod starts, but the pod can't start because the secret doesn't exist. This is a chicken-and-egg problem.

## Solution: Create Manual Secret First

Create the secret manually to get the pod running:

```bash
kubectl create secret generic authmanager-secrets \
  --namespace=muzika \
  --from-literal=POSTGRES_URL='jdbc:postgresql://digeper.postgres.database.azure.com:5432/postgres?sslmode=require' \
  --from-literal=POSTGRES_USERNAME='digeper' \
  --from-literal=POSTGRES_PASSWORD='TvajaMami31d' \
  --from-literal=JWT_SECRET='your-jwt-secret-key'
```

## Check Pod Events

To see the exact error:

```bash
kubectl describe pod -n muzika -l app=authmanager | grep -A 20 Events
```

This will show why the container config is failing (likely missing secret).

## After Creating Secret

1. The pod should start
2. Once running, the SecretProviderClass will sync secrets from Key Vault
3. On the next pod restart, it will use Key Vault secrets

## Verify Pod Starts

```bash
kubectl get pods -n muzika -l app=authmanager -w
```

Wait for the pod to be `Running` and `1/1 Ready`.

## Check Logs

```bash
kubectl logs -n muzika -l app=authmanager --tail=100 -f
```

The application should start successfully now.
