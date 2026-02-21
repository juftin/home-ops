# Research: External Secrets Operator with 1Password

## Chart & Image Versions

### Decision: ESO Helm Chart

- **Chosen**: `oci://ghcr.io/external-secrets/charts/external-secrets` tag `2.0.1`
- **Rationale**: Latest stable release at time of planning; confirmed by GitHub release `helm-chart-2.0.1`. Uses OCI registry consistent with all other charts in this cluster.
- **Alternatives considered**: ArtifactHub install via HTTPS — rejected in favour of OCI to match cluster convention.

### Decision: 1Password Connect Deployment Chart

- **Chosen**: `oci://ghcr.io/bjw-s-labs/helm/app-template` tag `4.6.2` (latest stable)
- **Rationale**: The official 1Password Connect Helm chart has been deprecated. The bjw-s `app-template` chart is the community-standard approach used by onedr0p/home-ops and kubesearch.dev examples. It provides flexible pod/container/service templating with minimal boilerplate.
- **Alternatives considered**: Official `1password/connect` Helm chart — deprecated upstream. Raw Deployment manifest — rejected; app-template provides cleaner values and Renovate tracking.

### Decision: 1Password Connect Image Tags

- **API container**: `ghcr.io/1password/connect-api:1.8.1`
- **Sync container**: `ghcr.io/1password/connect-sync:1.8.1`
- **Rationale**: `1.8.1` is the latest stable release at time of planning, pinned with SHA digests for reproducibility. Renovate will track updates automatically.
- **Digest pinning**: Both images should include `@sha256:…` digests alongside the tag, following the existing pattern in this cluster.

______________________________________________________________________

## Architecture Decisions

### Decision: Two-App Namespace Structure

- **Chosen**: Separate `external-secrets/` and `onepassword/` app directories under `kubernetes/apps/external-secrets/`, each with its own `ks.yaml` Flux Kustomization.
- **Rationale**: Mirrors the onedr0p/home-ops reference implementation. Separate Kustomizations allow explicit `dependsOn` ordering (1Password Connect waits for ESO CRDs), independent health-check expressions, and isolated reconciliation failure domains.
- **Alternatives considered**: Single combined Kustomization — rejected; it cannot express the deployment dependency between ESO and Connect cleanly.

### Decision: Bootstrap Secret as SOPS File

- **Chosen**: `kubernetes/apps/external-secrets/onepassword/app/secret.sops.yaml` — SOPS-encrypted, committed to the repository.
- **Rationale**: Consistent with all other secrets in the cluster. Keeps the cluster fully git-reproducible with no manual out-of-band provisioning steps. Flux's SOPS decryption (already configured on `cluster-apps`) handles it automatically.
- **Content**: Two keys — `1password-credentials.json` (base64-encoded Connect server credentials JSON) and `token` (Connect API token). These values must be obtained from the 1Password developer portal.
- **Alternatives considered**: Manual `kubectl apply` out-of-band — rejected; breaks reproducibility. Bootstrap script via `op` CLI — rejected; adds undocumented external dependency.

### Decision: ClusterSecretStore Scope

- **Chosen**: A single `ClusterSecretStore` named `onepassword`, cluster-wide.
- **Rationale**: All `ExternalSecret` resources in any namespace can reference the same store without per-namespace `SecretStore` resources. Reduces configuration duplication (DRY principle).
- **Vault targeted**: `Kubernetes` (name confirmed; each 1Password item maps to one logical secret group; custom fields map to individual Kubernetes secret keys).
- **Alternatives considered**: Namespace-scoped `SecretStore` — rejected; requires duplication per namespace.

### Decision: Connect Server Reliability

- **Chosen**: Single replica, rolling update strategy.
- **Rationale**: Homelab scale; ESO caches synced values as Kubernetes Secrets so a brief Connect restart does not delete existing secrets or disrupt applications.
- **Alternatives considered**: Two replicas — rejected; adds resource overhead and sync-cache coordination complexity with no meaningful uptime benefit at homelab scale.

### Decision: Connect Server Sync Cache Storage

- **Chosen**: `emptyDir` (ephemeral volume).
- **Rationale**: Cache is rebuilt quickly on restart; no persistent volume required. Matches onedr0p reference and avoids storage provisioner dependency.
- **Alternatives considered**: PVC — rejected; unnecessary complexity for homelab.

### Decision: Observability

- **Chosen**: ESO HelmRelease enables `serviceMonitor.enabled: true` and `grafanaDashboard.enabled: true`.
- **Rationale**: Consistent with the pattern already established by cert-manager (`prometheus.servicemonitor.enabled: true`) and flux-operator (`serviceMonitor.create: true`). Resources are inert until a Prometheus/Grafana stack is deployed.
- **Alternatives considered**: Skip until monitoring stack exists — rejected; retrofitting later is costlier and inconsistent with peer components.

______________________________________________________________________

## Integration Notes

### Flux Discovery of New Namespace

When Flux's kustomize-controller processes `path: ./kubernetes/apps` and finds no root-level `kustomization.yaml`, it generates an implicit kustomization in memory. Adding `kubernetes/apps/external-secrets/kustomization.yaml` places a new entry point that Flux's implicit scanning will discover and apply. This is the same mechanism used by all existing namespaces (cert-manager, network, flux-system, etc.).

### SOPS Decryption

The `cluster-apps` Kustomization already patches `decryption: provider: sops` onto all child Kustomizations. No explicit SOPS configuration is required in the `external-secrets` namespace kustomization — any `*.sops.yaml` file in any app subdirectory is automatically decrypted by Flux.

### Renovate Tracking

After deployment, Renovate will automatically detect:

- ESO chart tag in `ocirepository.yaml`
- bjw-s app-template tag in `ocirepository.yaml`
- 1Password Connect image tags in `helmrelease.yaml`

No Renovate configuration changes are required.

### ExternalSecret Refresh Interval

Default refresh interval for all `ExternalSecret` resources: `1h`. This satisfies SC-002 ("updates propagate within 1 hour") and is the established homelab convention.
