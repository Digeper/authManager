# AuthorizationManager

## What it does

User authentication and authorization service. Handles user registration, login, and JWT token generation/validation for the Muzika platform.

## Local Setup

1. Ensure PostgreSQL is running on `localhost:5432`
2. Create database `postgres` (or update `application.properties`)
3. Update `application.properties` with database credentials
4. Run: `mvn spring-boot:run`
5. Service starts on port `8091`

## Deployment

Deploy to Kubernetes namespace `muzika`:
```bash
kubectl apply -k k8s/
```

Image: `${ACR_NAME}.azurecr.io/muzika/authmanager:latest`

Requires: PostgreSQL database, Azure Key Vault secrets, ConfigMap
