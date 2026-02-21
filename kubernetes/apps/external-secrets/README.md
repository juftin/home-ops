# external-secrets

External Secrets Operator with 1Password Connect for Kubernetes secret management.

## Overview

- **ESO** (`external-secrets/`): The External Secrets Operator controller that syncs secrets from external providers into Kubernetes Secrets.
- **1Password Connect** (`onepassword/`): The 1Password Connect server that bridges ESO to the 1Password API. Exposes a `ClusterSecretStore` named `onepassword`.

## Bootstrap

Before deploying, the `onepassword-secret` bootstrap secret must be populated with real credentials:

1. Obtain 1Password Connect credentials from [1Password Developer Portal](https://developer.1password.com/docs/connect/get-started/)
2. Decrypt the placeholder secret:
   ```bash
   SOPS_AGE_KEY_FILE=age.key sops --decrypt --in-place kubernetes/apps/external-secrets/onepassword/app/secret.sops.yaml
   ```
3. Replace the placeholder values:
   - `1password-credentials.json`: base64-encoded credentials JSON from 1Password Connect setup
   - `token`: Connect API token
4. Re-encrypt:
   ```bash
   SOPS_AGE_KEY_FILE=age.key sops --encrypt --in-place kubernetes/apps/external-secrets/onepassword/app/secret.sops.yaml
   ```

## Adding a New Secret

See [`specs/001-external-secrets-1password/quickstart.md`](/specs/001-external-secrets-1password/quickstart.md) for the full workflow.

Quick reference:

1. Create a 1Password item in the **homelab** vault with custom fields
2. Create an `ExternalSecret` in your app's `app/` directory referencing `ClusterSecretStore/onepassword`
3. Run `task lint && task dev:validate`

Example `ExternalSecret`:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: my-app
  namespace: default
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword
  refreshInterval: 1h
  target:
    name: my-app-secret
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: my-app
```
