# Data Model: External Secrets Operator with 1Password

## Resource Graph

```
[Git Repository]
      │
      ▼
cluster-apps (Flux Kustomization)
  path: ./kubernetes/apps
      │
      ├──► external-secrets (Flux Kustomization)
      │         path: ./kubernetes/apps/external-secrets/external-secrets/app
      │         │
      │         ├── OCIRepository: external-secrets
      │         │     url: oci://ghcr.io/external-secrets/charts/external-secrets
      │         │     tag: 2.0.1
      │         │
      │         └── HelmRelease: external-secrets
      │               installs: ESO controller + webhook + cert-controller
      │               CRDs created: ExternalSecret, ClusterSecretStore, SecretStore, …
      │
      └──► onepassword (Flux Kustomization)   ← dependsOn: external-secrets
                path: ./kubernetes/apps/external-secrets/onepassword/app
                │
                ├── Secret: onepassword-secret   (SOPS-decrypted from secret.sops.yaml)
                │     keys:
                │       1password-credentials.json  (base64 Connect server credentials)
                │       token                        (Connect API token)
                │
                ├── OCIRepository: onepassword
                │     url: oci://ghcr.io/bjw-s-labs/helm/app-template
                │     tag: 4.6.2
                │
                ├── HelmRelease: onepassword
                │     containers:
                │       api   → ghcr.io/1password/connect-api:1.8.1
                │       sync  → ghcr.io/1password/connect-sync:1.8.1
                │     reads:  onepassword-secret (OP_SESSION / credentials.json)
                │     exposes: Service onepassword :80
                │     storage: emptyDir at /config
                │
                └── ClusterSecretStore: onepassword
                      provider: onepassword
                      connectHost: http://onepassword.external-secrets.svc.cluster.local
                      vault: Kubernetes
                      auth.secretRef → onepassword-secret / token


[Per-App Namespace]
      │
      └──► ExternalSecret: <app-name>         (defined in app's own app/ directory)
                secretStoreRef:
                  kind: ClusterSecretStore
                  name: onepassword
                target:
                  name: <kubernetes-secret-name>
                refreshInterval: 1h
                dataFrom / data → 1Password item key → field mapping
                      │
                      ▼
                Secret: <kubernetes-secret-name>   (materialized by ESO)
```

______________________________________________________________________

## Kubernetes Resource Definitions

### Namespace

```
Name:      external-secrets
Labels:    kubernetes.io/metadata.name: external-secrets
Managed:   namespace.yaml (Kustomize resource)
```

### Flux Kustomizations

| Resource      | Name               | Path                                                      | dependsOn        | healthChecks                                              |
| ------------- | ------------------ | --------------------------------------------------------- | ---------------- | --------------------------------------------------------- |
| Kustomization | `external-secrets` | `./kubernetes/apps/external-secrets/external-secrets/app` | —                | HelmRelease: external-secrets                             |
| Kustomization | `onepassword`      | `./kubernetes/apps/external-secrets/onepassword/app`      | external-secrets | HelmRelease: onepassword; ClusterSecretStore: onepassword |

### OCIRepositories

| Name               | URL                                                      | Tag     | Interval |
| ------------------ | -------------------------------------------------------- | ------- | -------- |
| `external-secrets` | `oci://ghcr.io/external-secrets/charts/external-secrets` | `2.0.1` | 15m      |
| `onepassword`      | `oci://ghcr.io/bjw-s-labs/helm/app-template`             | `4.6.2` | 15m      |

### HelmRelease: external-secrets

```
Chart source:   OCIRepository/external-secrets
Namespace:      external-secrets
Key values:
  leaderElect:              true
  serviceMonitor.enabled:   true
  grafanaDashboard.enabled: true
```

### HelmRelease: onepassword (via app-template)

```
Chart source:   OCIRepository/onepassword
Namespace:      external-secrets
Containers:
  api:
    image:    ghcr.io/1password/connect-api:1.8.1
    port:     80 (HTTP API)
    env:
      OP_SESSION:  secretKeyRef → onepassword-secret / 1password-credentials.json
      OP_HTTP_PORT: 80
      OP_BUS_PORT:  11220
      OP_BUS_PEERS: localhost:11221
  sync:
    image:    ghcr.io/1password/connect-sync:1.8.1
    port:     8081
    env:
      OP_SESSION:  secretKeyRef → onepassword-secret / 1password-credentials.json
      OP_HTTP_PORT: 8081
      OP_BUS_PORT:  11221
      OP_BUS_PEERS: localhost:11220
Strategy:   RollingUpdate (single replica)
Storage:    emptyDir at /config (XDG_DATA_HOME)
Service:    onepassword → port 80 (api container)
Security:   runAsNonRoot, readOnlyRootFilesystem, capabilities drop ALL
```

### Secret: onepassword-secret (bootstrap, SOPS-encrypted)

```
Name:       onepassword-secret
Namespace:  external-secrets
Source:     secret.sops.yaml (SOPS-encrypted, committed to repo)
Keys:
  1password-credentials.json   base64-encoded Connect server credentials JSON
  token                        Connect API token (plain string)
Consumers:
  - HelmRelease onepassword (OP_SESSION env var, both containers)
  - ClusterSecretStore onepassword (connectTokenSecretRef)
```

### ClusterSecretStore: onepassword

```
Name:           onepassword
Provider:       onepassword
connectHost:    http://onepassword.external-secrets.svc.cluster.local
vaults:
  Kubernetes: 1                (vault name → priority)
auth:
  secretRef:
    connectTokenSecretRef:
      name:      onepassword-secret
      namespace: external-secrets
      key:       token
Health:         Ready condition (healthCheckExpr monitored by onepassword Kustomization)
```

### ExternalSecret (per-app pattern)

```
Namespace:      <target-app-namespace>
secretStoreRef:
  kind:  ClusterSecretStore
  name:  onepassword
target:
  name:         <kubernetes-secret-name>
refreshInterval: 1h
dataFrom:
  - extract:
      key: <1password-item-name>      # item title in the "Kubernetes" vault
      # OR
data:
  - secretKey: <k8s-secret-key>
    remoteRef:
      key:      <1password-item-name>
      property: <1password-custom-field-name>
```

______________________________________________________________________

## 1Password Vault Structure

```
Vault: "Kubernetes"
  └── Item: <app-name>               (one item per logical secret group)
        Custom fields:
          FIELD_NAME_1: value1       → maps to Kubernetes secret key via ExternalSecret
          FIELD_NAME_2: value2
```

**Naming convention for 1Password items**: Use lowercase, hyphenated app names matching the
Kubernetes resource name (e.g., `cert-manager`, `cloudflare-dns`). Field names use
`SCREAMING_SNAKE_CASE` to match environment variable conventions.

______________________________________________________________________

## State Transitions: ExternalSecret Lifecycle

```
[Created] → Pending sync
    │
    ▼ (ESO controller reconciles)
[Synced] → Kubernetes Secret created / updated
    │
    ├── refreshInterval tick → re-fetch from 1Password → [Synced]
    │
    └── 1Password Connect unreachable → [SyncFailed]
              │  (existing Kubernetes Secret is RETAINED, not deleted)
              └── Connect recovers → [Synced]

[Deleted ExternalSecret] → Kubernetes Secret deleted (ESO cleanup)
```
