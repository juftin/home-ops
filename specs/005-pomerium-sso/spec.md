# Feature Specification: Replace Envoy OAuth with Pomerium SSO

**Feature Branch**: `005-pomerium-sso`
**Created**: 2026-11-16
**Status**: Draft
**Input**: User description: "Using Spec-Kit - replace our hand-rolled Google OAuth x Envoy infra with Pomerium: https://www.pomerium.com/docs/deploy/k8s/quickstart. Our existing set of OAuth Groups (Admins and Users) should be retained. If needed, you can use YAML anchors to handle this."

## Clarifications

### Session 2026-11-16

- Q: How should Pomerium routes and `Admins` / `Users` policies be structured so group lists stay DRY (with YAML anchors) and encrypted? → A: Consolidate all Pomerium-protected `Ingress` objects into a single SOPS-encrypted `List` manifest (`kubernetes/workloads/network/pomerium/ingresses.sops.yaml`) using `&admins` and `&users` YAML anchors for `ingress.pomerium.io/policy` (encrypted via `.sops.yaml` `encrypted_regex: "^(ingress\\.pomerium\\.io/policy)$"`), targeting each app's native Service in its own namespace.
- Q: How should Pomerium's Google IdP credentials, bootstrap secrets, and existing `Admins`/`Users` email lists be provisioned? → A: Store Google OAuth `client_id` / `client_secret` in SOPS-encrypted `kubernetes/workloads/network/pomerium/google-idp-secret.sops.yaml` (matching `network/` infra convention, encrypted with the repo's public age key using safe placeholders), use Pomerium quickstart's `pomerium-gen-secrets` Job (pinned to `v0.34.1`) for `pomerium/bootstrap`, and provide an idempotent local migration script (`scripts/migrate-oauth-to-pomerium.sh`) so the operator can transfer real emails and credentials from `origin/main` using their local `age.key`.
- Q: Which authenticate hostname and sign-out / access-denied page setup should be used? → A: Reuse `https://oauth.${SECRET_DOMAIN}` as `spec.authenticate.url` (preserving the existing Google Cloud Console redirect URI `https://oauth.<domain>/oauth2/callback`) and remove `apps/oauth-pages` in favor of Pomerium's built-in 403 Forbidden and `/.pomerium/sign_out` handling.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Identity-Aware SSO for Protected Applications (Priority: P1)

As the cluster operator, I want all currently OAuth-protected applications (AgentsView, Paseo, Herdr, Hermes Agent, OpenClaw, ArgoCD, and Grafana) to be protected by Pomerium with Google as the identity provider, replacing the hand-rolled Envoy Gateway OIDC gateways and policies, while keeping public and LAN-only applications (`echo`, `camply`, `ntfy`, `argocd-webhook`, `lunchmoney`) unchanged.

**Why this priority**: Replacing the authentication proxy layer for protected applications without breaking public or internal-only workloads is the core objective of the migration.

**Independent Test**: Visit a protected application URL in an unauthenticated browser; verify redirection to Google login via Pomerium, successful return to the requested application after authentication, and uninterrupted public/internal access on unprotected applications.

**Acceptance Scenarios**:

1. **Given** an unauthenticated user visits an admin-protected application (`agentsview`, `paseo`, `herdr`, `hermes`, `openclaw`, `argocd`), **When** the request arrives via Cloudflare Tunnel, **Then** Pomerium redirects the user to Google login and returns them to the requested URL upon completion.
2. **Given** a user visits a public application (`echo`, `camply`, `ntfy`, `webhooks`) or LAN-only application (`lunchmoney`), **When** the request arrives, **Then** it continues to bypass SSO and route directly through the public or internal gateway unchanged.
3. **Given** an authenticated user navigates between multiple protected applications in the same access group, **When** they open another protected application, **Then** their existing Pomerium session grants single sign-on access without prompting for Google login again.

______________________________________________________________________

### User Story 2 - Retain Admins and Users Access Groups (Priority: P2)

As the cluster operator, I want to retain the existing two-tier access control model (`Admins` and `Users`) so that administrative tools remain restricted to admin accounts while shared user dashboards (Grafana) allow both users and admins, with group membership defined centrally without duplicating email lists or exposing email addresses in plaintext in Git.

**Why this priority**: Authentication without retaining the existing `Admins` vs. `Users` authorization boundary would either lock out legitimate users or over-privilege non-admin users onto sensitive coding-agent and GitOps dashboards.

**Independent Test**: Authenticate as a `Users`-only account and verify access is granted to `grafana` but denied on admin applications (`agentsview`, `paseo`, `herdr`, `hermes`, `openclaw`, `argocd`); authenticate as an `Admins` account and verify access is granted to both tiers.

**Acceptance Scenarios**:

1. **Given** an authenticated Google account is in the `Admins` group, **When** they access any admin-tier or user-tier application, **Then** access is granted.
2. **Given** an authenticated Google account is in the `Users` group only (not `Admins`), **When** they access `grafana`, **Then** access is granted; **When** they access any admin-tier application, **Then** access is denied (403).
3. **Given** an authenticated Google account is in neither group, **When** they access any protected application, **Then** access is denied (fail-closed).
4. **Given** the repository is inspected in plaintext, **When** checking manifests and values files, **Then** no personal email addresses or OAuth credentials appear unencrypted in Git, and the `Admins` and `Users` definitions are maintained in a single SOPS-encrypted manifest using YAML anchors.

______________________________________________________________________

### User Story 3 - Decommission Envoy OAuth & Legacy OAuth Plumbing (Priority: P3)

As the cluster operator, I want all legacy Envoy OAuth infrastructure (`envoy-oauth-admin`, `envoy-oauth-users`, `envoy-oauth-internal` gateways, OAuth SecurityPolicies, OAuth header-limit EnvoyPatchPolicies, `oauth-denied-override` BackendTrafficPolicy, and `oauth-pages`) removed cleanly, with network policies, Cloudflare Tunnel ingress rules, DNS, and documentation updated to match Pomerium.

**Why this priority**: Leaving parallel OAuth gateways, SecurityPolicies, or stale network policies behind introduces drift, unused LoadBalancer IPs, and operational confusion.

**Independent Test**: Validate that offline cluster rendering (`task dev:validate:ci`) and repository linting (`task lint`) pass with zero references to removed Envoy OAuth gateways, and that workload network policies restrict backend pods to Pomerium proxy traffic (plus Tailscale where configured).

**Acceptance Scenarios**:

1. **Given** the legacy Envoy OAuth resources are removed, **When** offline manifest rendering and schema validation run across all workloads and ArgoCD bootstrap, **Then** all rendered manifests pass without errors or broken references.
2. **Given** coding-agent and dashboard workloads enforce pod-level network isolation, **When** Pomerium proxies authorized requests to backend pods, **Then** traffic from Pomerium is permitted while traffic from unrelated pods remains blocked.
3. **Given** a user logs out via `/.pomerium/sign_out` or is denied access, **When** Pomerium handles the request, **Then** they receive a clear confirmation or 403 access-denied response without redirect loops.

______________________________________________________________________

### Edge Cases

- What happens when a user's session expires or Pomerium restarts? Pomerium databroker uses persistent `file` storage backed by a `node-local` PVC (`1Gi`) with `Recreate` deployment strategy so active sessions survive pod restarts cleanly; expired sessions redirect seamlessly back to the requested URL after re-authentication.
- What happens when a protected application relies on WebSockets (Paseo, Herdr, OpenClaw, Hermes, Grafana, ArgoCD)? `ingress.pomerium.io/allow_websockets: "true"` is enabled on those routes so WebSocket upgrades pass through Pomerium cleanly.
- What happens when `argocd` has both Pomerium SSO in front and ArgoCD's own webhook endpoint (`webhooks.${SECRET_DOMAIN}/argocd/api/webhook`)? The webhook HTTPRoute remains on `envoy-external` without SSO challenge while the ArgoCD UI is protected by Pomerium.
- What happens during secret/email migration since the existing allowlists and Google OAuth client secret are SOPS-encrypted and the cluster age key is unavailable in isolated development environments? Encrypted SOPS placeholder files (encrypted with the repo's public age key) are committed so both `task dev:validate:ci` and `task dev:validate` succeed, and `scripts/migrate-oauth-to-pomerium.sh` automates transferring the real values from `origin/main` using the operator's `age.key`.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST deploy Pomerium Ingress Controller (`v0.34.1`) in Kubernetes following the Pomerium Kubernetes quickstart architecture, using the `Pomerium` global CRD (`ingress.pomerium.io/v1`) and `Ingress` resources (`ingressClassName: pomerium`) to front all OAuth-protected applications with Google as the identity provider.
- **FR-002**: All previously OAuth-protected applications (`agentsview`, `paseo`, `herdr`, `hermes-agent`, `openclaw`, `argocd`, and `grafana`) MUST be routed through Pomerium instead of Envoy OAuth Gateways.
- **FR-003**: Public applications (`echo`, `camply`, `ntfy`, `webhooks.${SECRET_DOMAIN}/argocd/api/webhook`) and LAN-only applications (`lunchmoney`) MUST remain on `envoy-external` and `envoy-internal` respectively without Pomerium authentication.
- **FR-004**: The system MUST retain the two access groups (`Admins` for `agentsview`, `paseo`, `herdr`, `hermes`, `openclaw`, `argocd`; `Users` — including admins — for `grafana`) and enforce fail-closed PPL authorization with no unauthenticated bypasses.
- **FR-005**: Access group definitions (`Admins` and `Users`) MUST be consolidated into `kubernetes/workloads/network/pomerium/ingresses.sops.yaml` (using `kind: List` with `&admins` and `&users` YAML anchors) and encrypted via `.sops.yaml` (`encrypted_regex: "^(ingress\\.pomerium\\.io/policy)$"`) so no email addresses appear in plaintext in Git.
- **FR-006**: Pomerium's Google IdP credentials (`client_id`, `client_secret`) MUST be stored in SOPS-encrypted `kubernetes/workloads/network/pomerium/google-idp-secret.sops.yaml`, and Pomerium's internal `bootstrap` secret (`shared_secret`, `cookie_secret`, `signing_key`) MUST be provisioned by Pomerium's `pomerium-gen-secrets` Job (pinned to `v0.34.1`).
- **FR-007**: Pomerium's `spec.authenticate.url` MUST reuse `https://oauth.${SECRET_DOMAIN}` (preserving the existing Google Cloud Console redirect URI `https://oauth.<domain>/oauth2/callback`) with wildcard TLS from `network/${SECRET_DOMAIN/./-}-production-tls`, and `apps/oauth-pages` MUST be removed in favor of Pomerium's built-in 403 and `/.pomerium/sign_out` handling.
- **FR-008**: Cloudflare Tunnel ingress rules MUST route all Pomerium-protected application hostnames and `oauth.${SECRET_DOMAIN}` to `https://pomerium-proxy.pomerium.svc.cluster.local:443` before the `*.${SECRET_DOMAIN}` wildcard rule, removing `oauth-users.${SECRET_DOMAIN}`.
- **FR-009**: Pod-level Cilium network policies for `agentsview`, `herdr`, `hermes-agent`, `openclaw`, and `paseo` MUST be updated to permit ingress from `pomerium-proxy` pods (`k8s:io.kubernetes.pod.namespace: pomerium`, `app.kubernetes.io/name: pomerium`, `app.kubernetes.io/component: proxy`) instead of the removed `envoy-oauth-admin` gateway.
- **FR-010**: Legacy Envoy OAuth infrastructure (`envoy-oauth-admin`, `envoy-oauth-users`, `envoy-oauth-internal`, `oauth-policy*.sops.yaml`, `oauth-client-secret.sops.yaml`, `oauth-header-limits.yaml`, `oauth-denied-override`, and `apps/oauth-pages`) MUST be removed, along with ArgoCD `SecurityPolicy` `ignoreDifferences` and obsolete `kube-prometheus-stack` `dnsendpoint.yaml` / `HTTPRoute`s on protected apps.
- **FR-011**: WebSocket connections (`ingress.pomerium.io/allow_websockets: "true"`) MUST be enabled for Paseo, Herdr, Hermes Agent, OpenClaw, Grafana, and ArgoCD.
- **FR-012**: All manifests MUST pass `task lint` and `task dev:validate:ci`, and an automated migration script (`scripts/migrate-oauth-to-pomerium.sh`) MUST be provided for the operator to migrate real SOPS secrets/emails locally with `age.key`.

### Key Entities

- **Pomerium Global Configuration (`Pomerium` CRD)**: Cluster-wide settings in `pomerium` namespace defining Google IdP, `https://oauth.${SECRET_DOMAIN}`, wildcard TLS certificate, `file` databroker storage, and bootstrap secret reference.
- **Protected Application `Ingress` (`ingresses.sops.yaml`)**: SOPS-encrypted `List` of `Ingress` resources (`ingressClassName: pomerium`) across protected app namespaces, referencing `&admins` and `&users` PPL policy anchors.
- **Google IdP Secret (`google-idp-secret.sops.yaml`)**: SOPS-encrypted Secret containing `client_id` and `client_secret` for Google OAuth 2.0.
- **Migration Helper (`scripts/migrate-oauth-to-pomerium.sh`)**: Idempotent script extracting `client_id`, `client_secret`, and `Admins`/`Users` email lists from `oauth-policy.sops.yaml` / `oauth-client-secret.sops.yaml` (or `origin/main` git ref) and writing SOPS-encrypted Pomerium manifests.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of OAuth-protected applications (`agentsview`, `paseo`, `herdr`, `hermes`, `openclaw`, `argocd`, `grafana`) require Google SSO via Pomerium and enforce `Admins` vs. `Users` authorization with zero unauthenticated bypasses.
- **SC-002**: 100% of public and internal-only applications (`echo`, `camply`, `ntfy`, `webhooks`, `lunchmoney`) remain accessible via `envoy-external` and `envoy-internal` with zero functional changes.
- **SC-003**: Zero plaintext email addresses, client secrets, or signing/cookie secrets are committed anywhere in the Git repository.
- **SC-004**: Email allowlist maintenance for `Admins` and `Users` is centralized in `kubernetes/workloads/network/pomerium/ingresses.sops.yaml` using YAML anchors.
- **SC-005**: `task lint` and `task dev:validate:ci` exit 0 across all Kubernetes workloads and ArgoCD bootstrap manifests after all Envoy OAuth resources are removed.
- **SC-006**: All repository documentation (`README.md`, `docs/ARCHITECTURE.md`, `docs/APP-ACCESS.md`, and OAuth/OIDC runbooks) accurately reflects Pomerium operations, credential setup, migration, and group management.
