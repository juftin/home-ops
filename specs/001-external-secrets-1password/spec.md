# Feature Specification: External Secrets Operator with 1Password

**Feature Branch**: `001-external-secrets-1password`
**Created**: 2026-02-21
**Status**: Draft
**Input**: User description: "Implement external-secrets with 1Password."

## Overview

The cluster currently manages secrets using SOPS encryption with an age key, and those existing
secrets will remain unchanged. This feature adds External Secrets Operator (ESO) as a
complementary secret management pathway — backed by 1Password — for **new** secrets going
forward. Existing SOPS-encrypted secrets are out of scope and will not be migrated.

A lightweight bridge service (1Password Connect) runs inside the cluster and exposes 1Password
vault items to ESO via a `ClusterSecretStore`. New applications declare what secrets they need
through `ExternalSecret` resources; ESO pulls the values and materializes them as native
Kubernetes Secrets automatically. Both SOPS and 1Password-backed secrets coexist in the cluster.

## Clarifications

### Session 2026-02-21

- Q: How should the bootstrap credentials secret (1Password Connect JSON + token) be provisioned on the cluster? → A: SOPS-encrypted file committed to the repo (same pattern as existing secrets).
- Q: Should ESO include observability configuration (ServiceMonitor, Grafana dashboard)? → A: Yes — include ServiceMonitor and Grafana dashboard, wired in now to match the pattern already established by cert-manager and flux-operator.
- Q: How many replicas should the 1Password Connect server run? → A: Single replica with rolling update strategy (homelab scale; ESO caches values so a brief outage does not delete existing Kubernetes Secrets).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - ESO and 1Password Connect Running in Cluster (Priority: P1)

As the homelab operator, I need the External Secrets Operator and the 1Password Connect server
deployed and healthy so that the secret synchronization infrastructure exists before any application
can use it.

**Why this priority**: Everything else depends on this foundation. Without a healthy ESO and a
reachable 1Password Connect endpoint the `ClusterSecretStore` cannot be ready and no
`ExternalSecret` can sync.

**Independent Test**: Can be fully tested by checking that both the ESO controller and the
1Password Connect pods reach a ready state and that the `ClusterSecretStore` reports `Ready: True`,
delivering a functional secret-sync layer with no application secrets involved.

**Acceptance Scenarios**:

1. **Given** the `external-secrets` namespace exists, **When** Flux reconciles the ESO HelmRelease,
   **Then** the ESO controller pod is running and healthy.
2. **Given** a valid 1Password Connect credentials secret is pre-provisioned, **When** Flux
   reconciles the 1Password Connect HelmRelease, **Then** both the API and sync containers reach
   ready state.
3. **Given** ESO and 1Password Connect are running, **When** the `ClusterSecretStore` is applied,
   **Then** its status shows `Ready: True` with no authentication errors.

______________________________________________________________________

### User Story 2 - Adding a New App Secret via 1Password (Priority: P2)

As the homelab operator, I want to add a secret for a new application by storing it in 1Password
and declaring an `ExternalSecret` manifest — without touching SOPS or age keys — so that new
secrets are centrally managed in 1Password from day one.

**Why this priority**: This is the primary operational benefit of the feature. Once the
infrastructure (P1) is healthy, every new secret must be provisionable via 1Password without any
interaction with SOPS tools.

**Independent Test**: Can be tested end-to-end by adding a test item in the 1Password Kubernetes
vault, creating an `ExternalSecret` referencing it, and confirming the resulting Kubernetes Secret
appears in the target namespace with the correct values.

**Acceptance Scenarios**:

1. **Given** a new item is created in the 1Password Kubernetes vault, **When** an `ExternalSecret`
   referencing that item is committed and reconciled, **Then** a Kubernetes Secret appears in the
   target namespace within 60 seconds.
2. **Given** an `ExternalSecret` is synced, **When** the value is updated in 1Password, **Then**
   the Kubernetes Secret is automatically updated within the configured refresh interval (≤ 1 hour).
3. **Given** a new secret is needed, **When** the operator follows the 1Password workflow, **Then**
   no SOPS tooling, age key access, or file re-encryption is required at any step.

______________________________________________________________________

### Edge Cases

- What happens when the 1Password Connect server is temporarily unreachable? ESO should report a
  sync failure on the `ExternalSecret` status but not delete the existing Kubernetes Secret.
- What happens when a referenced 1Password item or field does not exist? The `ExternalSecret` must
  enter a failed/not-ready state with a descriptive error message; no partial secret is created.
- What happens if a new `ExternalSecret` targets the same Kubernetes Secret name as an existing
  SOPS-managed resource? This must be avoided — new secrets managed by ESO must use distinct
  names that do not conflict with any existing SOPS-decrypted secrets.
- What happens if the bootstrap Connect credentials secret is missing at cluster start? ESO and the
  Connect server must enter a clear error state rather than silently failing.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The cluster MUST run an External Secrets Operator controller as a cluster-wide
  component in a dedicated `external-secrets` namespace.
- **FR-002**: A 1Password Connect server MUST run inside the cluster in the `external-secrets`
  namespace as the bridge between ESO and 1Password.
- **FR-003**: A `ClusterSecretStore` resource MUST be created that points to the in-cluster
  1Password Connect service, making it available to `ExternalSecret` resources in any namespace.
- **FR-004**: A dedicated 1Password vault (e.g., "Kubernetes") MUST hold all cluster secrets, with
  each logical secret group represented as a single vault item using custom fields.
- **FR-005**: A bootstrap Kubernetes Secret containing the 1Password Connect credentials (JSON
  credentials file and API token) MUST be provisioned via a SOPS-encrypted file committed to the
  repository, consistent with the existing secret management pattern. This secret MUST be
  decryptable by Flux before the Connect server HelmRelease is reconciled.
- **FR-006**: New secrets for new applications MUST be stored in 1Password and accessed via
  `ExternalSecret` resources. Existing SOPS-encrypted secrets remain defined in SOPS and are not
  replaced.
- **FR-007**: Each `ExternalSecret` MUST specify a refresh interval so that updates made in
  1Password propagate to the cluster automatically without manual intervention.
- **FR-008**: The `ClusterSecretStore` MUST report a `Ready` status that is visible and
  monitorable, enabling the operator to detect 1Password connectivity issues quickly.
- **FR-009**: The Flux Kustomization for the 1Password Connect app MUST declare a dependency on the
  ESO Kustomization to ensure correct deployment ordering.
- **FR-010**: The ESO HelmRelease MUST enable a Prometheus ServiceMonitor and a Grafana dashboard,
  consistent with the observability pattern established by cert-manager and flux-operator in this
  cluster. These become active when a monitoring stack is deployed; they impose no cost until then.
- **FR-011**: The 1Password Connect server MUST run as a single replica with a rolling update
  strategy. ESO caches the last-synced values in Kubernetes Secrets, so a brief Connect restart
  does not disrupt consuming applications.

### Key Entities

- **1Password Vault (Kubernetes)**: The authoritative store for new cluster secrets. Each item
  represents a logical group of related credentials; custom fields within the item map to individual
  secret keys. Existing secrets managed by SOPS may also be stored here for reference but the
  SOPS files remain the cluster-consumed source of truth for those secrets.
- **1Password Connect Server**: A lightweight server running in-cluster that authenticates to
  1Password and exposes vault items over a local HTTP API for ESO to query.
- **ClusterSecretStore**: A cluster-scoped ESO resource that describes how to reach the 1Password
  Connect server. All namespaces reference this store when defining `ExternalSecret` resources.
- **ExternalSecret**: A namespace-scoped ESO resource that declares which 1Password item and fields
  to sync, and what Kubernetes Secret to produce. Used exclusively for new secrets; existing
  SOPS-decrypted secrets remain unchanged.
- **Bootstrap Credentials Secret**: A Kubernetes Secret (`onepassword-secret`) holding the Connect
  server's JSON credentials and API token. Must exist before the Connect server can start; created
  out-of-band (e.g., via `op` CLI or manual cluster bootstrap step).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The `ClusterSecretStore` shows `Ready: True` within 5 minutes of the 1Password
  Connect server becoming healthy.
- **SC-002**: Any new secret value updated in 1Password propagates to the corresponding Kubernetes
  Secret within 1 hour without any manual operator action.
- **SC-003**: A new application secret can be added to the cluster in under 5 minutes by creating
  a 1Password item and committing an `ExternalSecret` manifest — no key management or encryption
  tooling required.
- **SC-004**: The operator can determine the sync status of any ESO-managed secret at a glance by
  inspecting the `ExternalSecret` resource status, including the last successful sync time and any
  errors.
- **SC-005**: Existing SOPS-managed secrets continue to function without any disruption throughout
  and after the deployment of the ESO + 1Password infrastructure.

## Assumptions

- The homelab operator already has a 1Password account and access to create a dedicated vault and
  generate Connect server credentials.
- The 1Password Connect credentials (JSON file and API token) are stored in a SOPS-encrypted file
  committed to the repository. Flux decrypts and applies this secret before the Connect server
  HelmRelease is reconciled, making bootstrap fully reproducible from git.
- The ESO `ClusterSecretStore` will use the `onepassword` provider pointing to the in-cluster
  Connect service at `http://onepassword.external-secrets.svc.cluster.local`.
- Secret refresh interval defaults to 1 hour, matching common homelab conventions.
- Existing SOPS-encrypted secret files and the age key remain in place indefinitely; this feature
  does not alter or remove any existing secret management infrastructure.
- Existing SOPS secret values may optionally be stored in 1Password for reference or auditability,
  but those 1Password items will not be consumed by the cluster — the SOPS files remain the source.
