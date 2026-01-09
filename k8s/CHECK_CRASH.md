# Debug Pod Crash After Cleanup

The pod is in BackOff state, which means the container is crashing. We need to see the logs to understand why.

## Check Pod Status

```bash
kubectl get pods -n muzika -l app=authmanager
```

## Get Crash Logs

```bash
# Get logs from the crashed pod
kubectl logs -n muzika authmanager-d58d7ff68-w5h8z --previous

# Or get logs from current pod
kubectl logs -n muzika -l app=authmanager --tail=100
```

## Check Pod Events

```bash
kubectl describe pod authmanager-d58d7ff68-w5h8z -n muzika
```

## Possible Causes

1. **Application not rebuilt**: After code changes, the Docker image needs to be rebuilt
2. **Compilation error**: The application might not compile
3. **Missing dependency**: StartupLifecycleListener might have been a required component (unlikely, but possible)
4. **Runtime error**: The application might be crashing for a different reason

## Next Steps

Once we see the logs, we can identify the exact issue and fix it.
