# Research: Headlamp + Flux Plugin

**Feature**: 002-headlamp-flux | **Date**: 2026-02-21

## Resolved Unknowns

### 1. Headlamp Service Name and Port

- **Decision**: Service name `headlamp` (from `fullnameOverride: headlamp`), port `80`
- **Rationale**: Headlamp chart exposes an HTTP service on port 80 by default, which forwards to the container port 4466. The `fullnameOverride` in the HelmRelease values sets the service name to `headlamp`.
- **Impact**: The `HTTPRoute` backendRef must specify `name: headlamp` and `port: 80`.

### 2. HTTPRoute Pattern

- **Decision**: Standalone `httproute.yaml` manifest (not embedded in HelmRelease values)
- **Rationale**: Headlamp uses the native headlamp Helm chart (not `app-template`), which does not have built-in `route:` support in its values. The `flux-instance` app uses the same standalone approach.
- **Alternatives considered**: Embedding route in HelmRelease values (only possible with `app-template` chart); Ingress resource (Gateway API HTTPRoute is the cluster standard).
- **Impact**: A separate `httproute.yaml` file is needed; echo app's embedded pattern does not apply.

### 3. Flux Variable Substitution for `${SECRET_DOMAIN}`

- **Decision**: `ks.yaml` must add `postBuild.substituteFrom` referencing the `cluster-secrets` Secret
- **Rationale**: The HTTPRoute hostname uses `${SECRET_DOMAIN}`. Flux performs this substitution at reconcile time via `postBuild.substituteFrom`. The existing `headlamp-app` branch `ks.yaml` is missing this block. Reference: echo's `ks.yaml` which already has the correct pattern.
- **Impact**: Without this addition, the HTTPRoute hostname would render as the literal string `headlamp.${SECRET_DOMAIN}` rather than `headlamp.juftin.dev`.

### 4. ExternalSecret — 1Password Field Name

- **Decision**: Field name `password` for the `headlamp-admin-token` 1Password item
- **Rationale**: The user confirmed this is an "existing password" item in 1Password, making it a Password-type item. The primary secret field in a 1Password Password item is `password`. The project's naming convention (per `specs/001-external-secrets-1password/quickstart.md`) uses `SCREAMING_SNAKE_CASE` for custom fields on Secure Note items, but standard Password items use `password` as the field name.
- **Alternatives considered**: Custom field with a different name — possible if the item was created with a custom field label, but `password` is the correct default for a Password-type item.
- **Impact**: `ExternalSecret` `remoteRef.property` must be set to `password`. If the actual field name differs, this is the one value to update.

### 5. ExternalSecret — ClusterSecretStore Name

- **Decision**: `onepassword` (confirmed from existing cluster config)
- **Rationale**: `kubernetes/apps/external-secrets/onepassword/app/clustersecretstore.yaml` defines `metadata.name: onepassword` pointing to 1Password Connect in the `external-secrets` namespace. This is the store used by all existing ExternalSecrets in the cluster.
- **Impact**: `ExternalSecret` `spec.secretStoreRef.name` must be `onepassword` with `kind: ClusterSecretStore`.

### 6. Namespace for All Resources

- **Decision**: `observability` for all new resources (ServiceAccount, ClusterRoleBinding subject namespace, ExternalSecret)
- **Rationale**: The existing `headlamp-app` branch deploys Headlamp into the `observability` namespace. All associated resources must be in the same namespace for the ServiceAccount reference to work. The `ClusterRoleBinding` is cluster-scoped but references the `headlamp-admin` SA in the `observability` namespace.
- **Impact**: All manifests set `namespace: observability`.

### 7. RBAC — ClusterRoleBinding vs RoleBinding

- **Decision**: `ClusterRoleBinding` (cluster-scoped)
- **Rationale**: Headlamp needs visibility across all namespaces for the dashboard to be useful. A `RoleBinding` would restrict visibility to a single namespace. User explicitly chose `cluster-admin` access.
- **Alternatives considered**: `RoleBinding` to `view` in each namespace — rejected because Headlamp dashboard needs cross-namespace visibility and secret access.
- **Impact**: A `ClusterRoleBinding` resource (not namespaced) is required.

## Implementation Decisions Summary

| Area                   | Decision                                                                |
| ---------------------- | ----------------------------------------------------------------------- |
| Headlamp service name  | `headlamp`                                                              |
| Headlamp service port  | `80`                                                                    |
| HTTPRoute pattern      | Standalone `httproute.yaml`                                             |
| Gateway                | `envoy-external` in `network` namespace, section `https`                |
| Hostname               | `headlamp.${SECRET_DOMAIN}` (substituted by Flux)                       |
| ClusterSecretStore     | `onepassword`                                                           |
| 1Password item         | `headlamp-admin-token`                                                  |
| 1Password field        | `password`                                                              |
| Target K8s secret name | `headlamp-admin-token` (matches item name, consistent with convention)  |
| ServiceAccount         | `headlamp-admin` in `observability`                                     |
| ClusterRole            | `cluster-admin` (justified exception — see plan.md Complexity Tracking) |
| Namespace              | `observability`                                                         |
| Variable substitution  | `postBuild.substituteFrom: cluster-secrets` in `ks.yaml`                |
