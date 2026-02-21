# Feature Specification: Headlamp + Flux Plugin

**Feature Branch**: `002-headlamp-flux`
**Created**: 2026-02-21
**Status**: Draft
**Input**: User description: "I want to visualize my cluster and what flux is doing with headlamp and the flux plugin for headlamp. The credentials should be synced to 1Password. There is an existing password there called headlamp-admin-token"

## Existing Work (headlamp-app branch)

The `headlamp-app` branch contains a partial implementation:

- `kubernetes/apps/observability/headlamp/app/helmrelease.yaml` — OCIRepository + HelmRelease deploying Headlamp chart v0.33.0 into the `observability` namespace; Flux plugin loaded via init container (`ghcr.io/headlamp-k8s/headlamp-plugin-flux:v0.4.0`); chart configured with `serviceAccount.create: false` and `clusterRoleBinding.create: false` (both expected to be pre-created).
- `kubernetes/apps/observability/headlamp/app/kustomization.yaml` — references only `helmrelease.yaml`; no ExternalSecret yet.
- `kubernetes/apps/observability/headlamp/ks.yaml` — Flux Kustomization targeting the `observability` namespace.
- `kubernetes/apps/observability/kustomization.yaml` — namespace-level kustomization referencing headlamp's `ks.yaml`.

**What is missing** from the existing branch:

1. A `ServiceAccount` named `headlamp-admin` in the `observability` namespace.
2. A `ClusterRoleBinding` granting `headlamp-admin` cluster-wide read access.
3. An `ExternalSecret` syncing the `headlamp-admin-token` item from 1Password into a Kubernetes secret.

## Clarifications

### Session 2026-02-21

- Q: What access level should the `headlamp-admin` ClusterRoleBinding grant? → A: `cluster-admin` (full read/write access to all resources including secrets)
- Q: How should Headlamp be accessed? → A: Exposed externally at `headlamp.${SECRET_DOMAIN}` via HTTPRoute (Gateway API)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Access Cluster Dashboard (Priority: P1)

As a cluster operator, I want to open Headlamp in a browser and see an overview of my Kubernetes cluster — namespaces, workloads, pods, and their statuses — so that I can understand the health of my homelab at a glance.

**Why this priority**: Core value of the feature; everything else depends on Headlamp being accessible and functional.

**Independent Test**: Can be fully tested by navigating to the Headlamp URL, logging in with the admin token sourced from 1Password, and verifying that the cluster resource list renders.

**Acceptance Scenarios**:

1. **Given** Headlamp is deployed and the admin token is synced from 1Password, **When** I open the Headlamp URL, **Then** I can authenticate and see the cluster's namespaces and workloads.
2. **Given** I am logged in to Headlamp, **When** I click on any namespace, **Then** I see a list of pods and their current status.
3. **Given** the admin token rotates in 1Password, **When** the secret is re-synced, **Then** Headlamp continues to work without manual intervention.

______________________________________________________________________

### User Story 2 - Visualize Flux GitOps State (Priority: P2)

As a cluster operator, I want to see the state of all Flux resources — Kustomizations, HelmReleases, GitRepositories, and their sync status — inside Headlamp via the Flux plugin, so that I can quickly identify reconciliation failures or drift.

**Why this priority**: The Flux plugin is the primary differentiator over a plain Kubernetes dashboard and delivers the core GitOps observability value.

**Independent Test**: Can be fully tested by navigating to the Flux section in Headlamp and verifying that HelmReleases and Kustomizations appear with their current ready/failed status.

**Acceptance Scenarios**:

1. **Given** the Flux plugin is installed in Headlamp, **When** I open the Flux section, **Then** I see all Kustomizations and HelmReleases with their sync status.
2. **Given** a HelmRelease is failing, **When** I click on it in Headlamp, **Then** I can see the failure reason and last reconcile attempt.
3. **Given** a Kustomization is suspended, **When** I view it in Headlamp, **Then** it is clearly marked as suspended.

______________________________________________________________________

### User Story 3 - Credentials Available via 1Password (Priority: P3)

As a cluster operator, I want the Headlamp admin token to be automatically pulled from 1Password (the `headlamp-admin-token` item) into the cluster as a Kubernetes secret, so that I never need to manage it manually and it stays in sync with the authoritative source.

**Why this priority**: Supports security hygiene and operational simplicity; Headlamp is still accessible without this if credentials are managed manually, making it lower priority than the dashboard itself.

**Independent Test**: Can be fully tested by verifying that the Kubernetes secret containing the admin token exists and matches the value stored in 1Password under `headlamp-admin-token`, without any manual secret creation step.

**Acceptance Scenarios**:

1. **Given** an ExternalSecret is configured pointing to the `headlamp-admin-token` 1Password item, **When** the secret is reconciled, **Then** a Kubernetes secret containing the token exists in the Headlamp namespace.
2. **Given** the value of `headlamp-admin-token` changes in 1Password, **When** the ExternalSecret is next reconciled, **Then** the in-cluster secret is updated automatically.

______________________________________________________________________

### Edge Cases

- What happens when the `headlamp-admin-token` item does not exist in 1Password or the ExternalSecret cannot fetch it? The Headlamp pod should still start, but login will fail until the secret is available.
- What happens when Headlamp loses connectivity to the cluster API? The UI should display a clear error state rather than a blank screen.
- What happens if the Flux plugin version is incompatible with the installed Flux version? The plugin section should degrade gracefully without breaking the core Headlamp UI.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: ✅ Headlamp MUST be deployed to the `observability` namespace and managed by Flux (OCIRepository + HelmRelease). *(Exists on headlamp-app branch)*
- **FR-002**: ✅ The Flux plugin MUST be installed in Headlamp so that Flux resources (Kustomizations, HelmReleases, GitRepositories, OCI repositories) are visible and navigable. *(Implemented via init container on headlamp-app branch)*
- **FR-003**: A `ServiceAccount` named `headlamp-admin` MUST exist in the `observability` namespace for Headlamp to use as its cluster identity.
- **FR-004**: A `ClusterRoleBinding` MUST bind the `headlamp-admin` ServiceAccount to the `cluster-admin` ClusterRole, granting full access to all cluster resources including secrets.
- **FR-005**: An `ExternalSecret` MUST sync the `headlamp-admin-token` item from 1Password into a Kubernetes secret in the `observability` namespace.
- **FR-006**: The Headlamp HelmRelease MUST reference the synced secret (or ServiceAccount token) as the authentication credential for login.
- **FR-007**: The `app/kustomization.yaml` MUST be updated to include all new resources (ExternalSecret, ServiceAccount, ClusterRoleBinding, HTTPRoute) so Flux reconciles them.
- **FR-008**: An HTTPRoute MUST expose Headlamp externally at `headlamp.${SECRET_DOMAIN}` via the `envoy-external` Gateway in the `network` namespace over HTTPS.

### Key Entities

- **Headlamp HelmRelease**: Deploys the Headlamp web dashboard; configured with `serviceAccount.create: false` and `clusterRoleBinding.create: false`, expecting both to be pre-created.
- **headlamp-admin ServiceAccount**: The Kubernetes identity used by Headlamp to communicate with the cluster API; must exist before Headlamp starts.
- **ClusterRoleBinding**: Binds `headlamp-admin` to the `cluster-admin` ClusterRole, granting full access to all cluster resources including secrets.
- **ExternalSecret**: Instructs External Secrets Operator to fetch `headlamp-admin-token` from 1Password and write it as a Kubernetes secret in the `observability` namespace.
- **Admin Token Secret**: The resulting Kubernetes secret containing the bearer token used to log in to the Headlamp UI.
- **HTTPRoute**: Gateway API resource routing `headlamp.${SECRET_DOMAIN}` to the Headlamp service via the `envoy-external` Gateway over HTTPS.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A cluster operator can open `https://headlamp.${SECRET_DOMAIN}`, authenticate with the token from 1Password, and view all cluster namespaces within 10 seconds of page load.
- **SC-002**: All Flux Kustomizations and HelmReleases are visible in the Headlamp Flux plugin view with their current sync status.
- **SC-003**: The admin token secret exists in the cluster and reflects the current value in 1Password within the ExternalSecret refresh interval (≤1 hour by default).
- **SC-004**: No manual secret creation steps are required after the initial Flux deployment reconciles.
- **SC-005**: Headlamp continues operating normally after the admin token is rotated in 1Password and the ExternalSecret re-syncs.

## Assumptions

- The External Secrets Operator is already installed and configured with a 1Password ClusterSecretStore in this cluster.
- The `headlamp-admin-token` item already exists in 1Password with the correct token value.
- Headlamp is exposed externally at `headlamp.${SECRET_DOMAIN}` via HTTPRoute through the `envoy-external` Gateway (consistent with other apps in this cluster such as `flux-webhook`); port-forwarding is not required.
- Headlamp is deployed in the `observability` namespace, consistent with the existing `headlamp-app` branch.
- The `headlamp-admin` ServiceAccount will use the token from the synced secret (or a separately created ServiceAccount token) as the Headlamp login credential.
- The Flux plugin is already handled via the init container approach on the existing branch; no changes needed there.
