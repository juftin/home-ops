# Feature Specification: Pomerium Authentication with YAML Anchors

**Feature Branch**: `007-pomerium-auth`  
**Created**: 2026-10-29  
**Status**: Draft  
**Input**: User description: "Swap current custom app + Envoy native OIDC setup with Pomerium using the YAML Anchors strategy."

## Overview

Replace the existing Envoy Gateway native OIDC and custom `oauth-pages` static NGINX setup with Pomerium as an identity-aware authorization engine. The replacement eliminates multi-Gateway sprawl (`envoy-oauth-admin`, `envoy-oauth-users`, `envoy-oauth-internal`), frees three LoadBalancer IPs, retires the custom `oauth-pages` NGINX deployment, removes low-level Envoy HTTP header JSON patches, and establishes clean role-based access control (`admins` and `users`) using declarative YAML anchors.

---

## User Scenarios & Testing

### User Story 1 - Protect Applications via Unified Gateway with Role Access (Priority: P1)

As the cluster operator, I want all OAuth-protected applications to be exposed through a single unified ingress Gateway while enforcing role separation (`admins` vs `users`) at the route/policy level, so that adding or reconfiguring an app does not require provisioning dedicated Kubernetes Gateways or allocating new LoadBalancer IP addresses.

**Why this priority**: Core functional capability. Eliminates Gateway sprawl and establishes the new authorization path for protected applications.

**Independent Test**: Can be verified by accessing an admin application (e.g. `paseo.${SECRET_DOMAIN}`) with an admin email account and gaining access, while non-admin users receive an access-denied page, all through the unified `envoy-external` ingress.

**Acceptance Scenarios**:

1. **Given** an unauthenticated user navigates to an admin-restricted app (e.g. `https://paseo.${SECRET_DOMAIN}`), **When** they request the page, **Then** they are redirected to Google login via Pomerium's authenticate endpoint (`https://authenticate.${SECRET_DOMAIN}`).
2. **Given** an authenticated user whose email is in the `admins` anchor list, **When** they complete login, **Then** they are redirected to the requested admin app with valid session credentials.
3. **Given** an authenticated user whose email is in the `users` anchor list but not `admins`, **When** they attempt to access an admin-restricted app, **Then** Pomerium displays a built-in 403 Forbidden page indicating unauthorized access.
4. **Given** an authenticated user in the `users` list, **When** they access a user-tiered app (e.g. `https://grafana.${SECRET_DOMAIN}`), **Then** access is granted.

---

### User Story 2 - Maintain Role Whitelists via YAML Anchors (Priority: P2)

As the cluster operator, I want to define user access groups (`admins` and `users`) once using YAML anchors in the configuration repository, so that group memberships are centralized, easy to audit, and inherited by all relevant routes without duplicate lists or case-sensitivity pitfalls.

**Why this priority**: Eliminates repetitive, duplicated allowlists across multiple manifests and ensures strict GitOps consistency across all protected services.

**Independent Test**: Can be tested by adding a new email to the `users` anchor list in configuration, syncing via GitOps, and verifying that the user can immediately access all user-tiered services while remaining blocked from admin services.

**Acceptance Scenarios**:

1. **Given** the access policy file defines `groups.admins: &admins` and `groups.users: &users`, **When** a route specifies `allowed_users: *admins`, **Then** only emails defined in the `admins` anchor are authorized.
2. **Given** the `users` anchor includes `*admins` plus additional user emails, **When** a route specifies `allowed_users: *users`, **Then** both admin and user email accounts are authorized.
3. **Given** a new email is added to the `admins` anchor, **When** the change is deployed, **Then** that email automatically gains access to all admin-scoped applications without modifying individual app configurations.

---

### User Story 3 - Native Authentication Lifecycle & Error UX (Priority: P3)

As a user of protected cluster applications, I want clean, built-in login redirects, access-denied messages, and explicit logout workflows without encountering broken redirect loops or requiring custom static NGINX helper pods.

**Why this priority**: Resolves the operational burden of maintaining custom HTML, JS fetch scripts, and route rewrites in `oauth-pages`.

**Independent Test**: Can be tested by visiting `/.pomerium/sign_out`, verifying session cookies are invalidated across all cluster subdomains, and confirming that the user is presented with a standard logged-out confirmation screen.

**Acceptance Scenarios**:

1. **Given** a user is logged into any protected application, **When** they visit the sign-out endpoint (`/.pomerium/sign_out`), **Then** their session cookie is invalidated and they see Pomerium's built-in logout confirmation screen.
2. **Given** a logged-out user subsequently visits a protected app, **When** the request arrives, **Then** they are prompted with a fresh Google authentication challenge.
3. **Given** an authenticated user lacks permission for a route, **When** access is denied, **Then** Pomerium renders its native access-denied page displaying the authenticated identity and target service without redirecting back to the app in a loop.

---

### User Story 4 - Decommission Legacy OIDC & Custom Plumbing (Priority: P4)

As the cluster operator, I want to retire `oauth-pages`, the low-level `EnvoyPatchPolicy` JSON patches, the 403 response overrides, and explicit per-app Cloudflare Tunnel ingress rules, so that cluster configuration is simpler and uses standard ingress abstractions.

**Why this priority**: Reduces maintenance overhead, removes technical debt, and frees cluster IP and compute resources.

**Independent Test**: Can be tested by verifying that `oauth-pages` deployment, `oauth-header-limits.yaml`, and `envoy-oauth-*` gateways can be deleted with zero regression in app accessibility.

**Acceptance Scenarios**:

1. **Given** Pomerium is active, **When** the `oauth-pages` deployment and service are removed from namespace `default`, **Then** all authentication and logout flows continue operating normally.
2. **Given** `envoy-oauth-admin`, `envoy-oauth-users`, and `envoy-oauth-internal` Gateways are removed, **When** inspecting cluster LoadBalancer IPs, **Then** IPs `192.168.1.149`, `192.168.1.150`, and `192.168.1.151` are released back to the pool.
3. **Given** Cloudflare Tunnel is updated, **When** per-app OAuth routes are removed from `cloudflare-tunnel`'s `config.yaml`, **Then** wildcard routing `*.${SECRET_DOMAIN}` successfully routes all traffic to `envoy-external`.

---

## Edge Cases

- **Large Cookie / Header Sizes**: Google ID tokens with extensive claims can exceed default Envoy header buffer sizes. Pomerium manages its own encrypted session cookie chunking on the client and in-memory session cache, eliminating Envoy 431/400 errors without requiring `EnvoyPatchPolicy` listener overrides.
- **Email Case Sensitivity**: Google OIDC returns lowercase emails, but humans may enter mixed-case emails in Git. Pomerium's policy evaluator performs case-insensitive email normalization.
- **Google OAuth Refresh Tokens**: When a user's Google session token expires during an active browser session, Pomerium uses background refresh tokens to seamlessly renew the session without interrupting the user.
- **Fail-Closed on Secret Loss**: If the Google client secret or Pomerium shared secrets are unavailable, Pomerium fails closed and blocks all access rather than permitting unauthenticated traffic.
- **Wildcard Subdomain Cookie Scope**: Session cookies must be scoped to the parent domain (e.g. `.${SECRET_DOMAIN}`) so that logging in once allows seamless navigation across all authorized apps in the cluster.

---

## Requirements

### Functional Requirements

- **FR-001**: The cluster MUST deploy Pomerium in the `network` namespace as the centralized identity-aware authorization provider.
- **FR-002**: Pomerium MUST authenticate users against Google OIDC using a single OAuth 2.0 Web Application client credential.
- **FR-003**: Google Cloud Console MUST require only one redirect URI: `https://authenticate.${SECRET_DOMAIN}/oauth2/callback`.
- **FR-004**: Pomerium configuration MUST define user groups using YAML anchors (`&admins` and `&users`) in its configuration values.
- **FR-005**: The `users` group anchor MUST include `*admins` to guarantee admin accounts retain access to user-tier applications without duplicate list management.
- **FR-006**: Pomerium routes MUST enforce authorization based on group assignment:
  - Admin apps (`paseo`, `herdr`, `hermes`, `openclaw`, `argocd`) MUST require `allowed_users: *admins`.
  - User apps (`grafana`) MUST require `allowed_users: *users`.
- **FR-007**: Envoy Gateway MUST connect to Pomerium via `SecurityPolicy.spec.extAuth` (or Pomerium proxy route), allowing all external traffic to enter through the existing `envoy-external` Gateway.
- **FR-008**: The dedicated OAuth Gateways (`envoy-oauth-admin`, `envoy-oauth-users`, `envoy-oauth-internal`) and their assigned LoadBalancer IPs MUST be retired.
- **FR-009**: The custom `oauth-pages` NGINX application, its ConfigMap, URL rewrites, and the `oauth-pages-public` SecurityPolicy MUST be deleted.
- **FR-010**: The low-level `EnvoyPatchPolicy` JSON patches in `oauth-header-limits.yaml` MUST be removed.
- **FR-011**: Cloudflare Tunnel configuration MUST route all app hostnames through the wildcard `*.${SECRET_DOMAIN}` to `envoy-external`, with an explicit route added only for `authenticate.${SECRET_DOMAIN}`.
- **FR-012**: Pomerium session cookies MUST be securely scoped to `.${SECRET_DOMAIN}` with `Secure`, `HttpOnly`, and `SameSite` protections enabled.
- **FR-013**: Secrets (Google OAuth client secret, Pomerium shared secret, and cookie encryption secret) MUST be stored encrypted via SOPS or 1Password `ExternalSecret`.

---

### Key Entities

- **Pomerium Control & Data Plane**: The Pomerium service running in `network`, orchestrating OIDC redirects, session cookie encryption, and extAuth / proxy policy evaluations.
- **Group Anchors (`&admins`, `&users`)**: Reusable YAML structures containing lists of approved Google email addresses defined once in values.
- **Pomerium Policy**: Declarative route rules specifying source URL (`from`), backend target (`to`), and access criteria (`allowed_users`).
- **Unified Gateway (`envoy-external`)**: The primary Gateway API entry point handling all ingress traffic, terminating TLS, and delegating auth checks to Pomerium.
- **Authenticate Host (`authenticate.${SECRET_DOMAIN}`)**: The dedicated endpoint hosting Pomerium's OIDC callback, user profile, and sign-out endpoints.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% of unauthenticated requests to protected endpoints redirect to Google authentication via `https://authenticate.${SECRET_DOMAIN}`.
- **SC-002**: 100% of requests from authenticated users not matching the route's allowed group are denied with Pomerium's native 403 page; zero requests enter redirect loops.
- **SC-003**: Total Kubernetes Gateways for HTTP/HTTPS ingress is reduced from five (`envoy-external`, `envoy-internal`, `envoy-oauth-admin`, `envoy-oauth-users`, `envoy-oauth-internal`) to two (`envoy-external`, `envoy-internal`).
- **SC-004**: Three LoadBalancer IPs (`192.168.1.149`, `192.168.1.150`, `192.168.1.151`) are released and freed in Cilium IPAM / MetalLB.
- **SC-005**: All custom NGINX static error files (`denied.html`, `logged-out.html`) and associated route rewrites in `oauth-pages` are permanently deleted.
- **SC-006**: All 122 lines of `EnvoyPatchPolicy` raw JSON patches (`oauth-header-limits.yaml`) are completely removed without causing HTTP 431/400 errors.
- **SC-007**: Modifying an email in a group anchor updates access permissions across all associated applications in a single GitOps commit.
