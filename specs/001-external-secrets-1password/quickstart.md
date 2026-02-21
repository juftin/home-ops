# Quickstart: Adding a New Secret via 1Password

This guide covers the full workflow for provisioning a new Kubernetes secret using the
External Secrets Operator + 1Password integration. **Existing SOPS secrets are unaffected.**

______________________________________________________________________

## Prerequisites

- 1Password Connect is deployed and `ClusterSecretStore/onepassword` shows `Ready: True`
- You have access to the 1Password **homelab** vault
- You are working on a feature branch (never directly on `main`)

______________________________________________________________________

## Step 1 — Create the Secret in 1Password

### Option A — Using the 1Password app

1. Open 1Password and navigate to the **homelab** vault

2. Create a new item (recommended type: **Secure Note** or **Login**)

3. Name the item to match your app (e.g., `my-app` — lowercase, hyphenated)

4. Add custom fields for each secret value using `SCREAMING_SNAKE_CASE` field names:

   ```
   API_KEY          = "abc123..."
   DATABASE_URL     = "postgres://..."
   ```

5. Save the item

### Option B — Using the `op` CLI

```bash
# Sign in (if not already authenticated)
op signin

# Create a Secure Note item in the homelab vault with custom fields
op item create \
  --category "Secure Note" \
  --vault homelab \
  --title my-app \
  "API_KEY[password]=abc123..." \
  "DATABASE_URL[text]=postgres://..."

# Verify the item was created
op item get my-app --vault homelab --fields label=API_KEY,label=DATABASE_URL

# List all items in the vault
op item list --vault homelab
```

> **Naming convention**: Item name = app name (e.g., `cert-manager`, `cloudflare-dns`).
> Field names = environment variable style (`API_KEY`, `DATABASE_PASSWORD`).

______________________________________________________________________

## Step 2 — Create the ExternalSecret Manifest

In your app's `app/` directory, create `externalsecret.yaml`:

```yaml
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/external-secrets.io/externalsecret_v1.json
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
        key: my-app           # must match the 1Password item name exactly
```

Reference it in your app's `app/kustomization.yaml`:

```yaml
resources:
  - ./kustomization.yaml
  - ./ocirepository.yaml
  - ./helmrelease.yaml
  - ./externalsecret.yaml    # add this line
```

______________________________________________________________________

## Step 3 — Validate Locally

```bash
task lint             # auto-fix formatting (run twice if needed)
task dev:validate     # render all HelmReleases and Kustomizations — no cluster required
```

Both must pass before pushing.

______________________________________________________________________

## Step 4 — Deploy and Verify

```bash
task dev:start        # push branch, patch GitRepository to branch, reconcile

# Check ExternalSecret status
kubectl get externalsecret my-app -n default

# Check that the Kubernetes Secret was created
kubectl get secret my-app-secret -n default

# See sync details
kubectl describe externalsecret my-app -n default
```

A healthy ExternalSecret will show:

```
Status:
  Conditions:
    Reason:   SecretSynced
    Status:   True
    Type:     Ready
  Refresh Time: <timestamp>
```

______________________________________________________________________

## Step 5 — Reference the Secret in Your App

```yaml
# In your app's HelmRelease values:
env:
  API_KEY:
    valueFrom:
      secretKeyRef:
        name: my-app-secret
        key: API_KEY
```

______________________________________________________________________

## Step 6 — Wrap Up

```bash
task dev:stop         # restore cluster to main
```

Open a pull request. CI runs `flux-local test` to validate the ExternalSecret renders correctly.

______________________________________________________________________

## Troubleshooting

| Symptom                                     | Likely Cause                      | Fix                                                                       |
| ------------------------------------------- | --------------------------------- | ------------------------------------------------------------------------- |
| ExternalSecret status: `SecretSyncedError`  | 1Password item name mismatch      | Check item title in "homelab" vault matches `key:` in ExternalSecret      |
| ExternalSecret status: `NoSecretStoreFound` | ClusterSecretStore not ready      | Check `kubectl get clustersecretstore onepassword` — ensure `Ready: True` |
| Secret created but missing keys             | Field names don't match           | Field names in 1Password must exactly match `property:` in ExternalSecret |
| `ClusterSecretStore` not ready              | 1Password Connect pod not running | Check `kubectl get pods -n external-secrets`                              |

______________________________________________________________________

## Checking Secret Sync Status

```bash
# List all ExternalSecrets cluster-wide
kubectl get externalsecrets -A

# Check ClusterSecretStore health
kubectl get clustersecretstore onepassword

# View ESO controller logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50
```

______________________________________________________________________

## Managing 1Password Items with `op` CLI

```bash
# Sign in
op signin

# List all items in the homelab vault
op item list --vault homelab

# Get all fields for an item
op item get my-app --vault homelab

# Get a specific field value
op item get my-app --vault homelab --fields label=API_KEY

# Update a field value
op item edit my-app --vault homelab "API_KEY[password]=new-value"

# Add a new field to an existing item
op item edit my-app --vault homelab "NEW_FIELD[text]=some-value"

# Delete an item
op item delete my-app --vault homelab
```

> [!NOTE]
> The `op` CLI must be signed into the same 1Password account as the Connect server.
> If Connect was configured for a different account, manage items from that account's app or CLI session.
