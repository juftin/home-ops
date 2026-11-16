# Feature Specification: Authentik Identity & Access Management (IAM)

**Feature Branch**: `008-authentik-auth`  
**Created**: 2026-10-29  
**Status**: Draft  
**Input**: User description: "Implement Authentik as a centralized Identity Provider (IdP) and access proxy on the cluster, integrating with Envoy Gateway via extAuth, replacing individual app authentication (SSO), and retiring custom OAuth plumbing."

## Overview

Deploy [Authentik](https://goauthentik.io/) in the cluster as a comprehensive Identity Provider (IdP) and access control engine. This architecture solves two major limitations of the current infrastructure:
1. **Perimeter Auth Simplification**: Replaces Envoy Gateway's native OIDC filter, the three dedicated OAuth Gateways (`envoy-oauth-admin`, `envoy-oauth-users`, `envoy-oauth-internal`), the custom `oauth-pages` NGINX deployment, and the low-level `EnvoyPatchPolicy` JSON patches with a unified forward-auth outpost connected to `envoy-external` via Envoy Gateway's `SecurityPolicy.spec.extAuth`.
2. **True Application-Level Single Sign-On (SSO)**: Replaces local credentials and fragmented authentication across cluster applications (e.g., Grafana and ArgoCD) by configuring them as native OIDC clients against Authentik. Users log in once using Google SSO or Passkeys, and Authentik passes authenticated identities, claims, and role mappings (`admin` vs `viewer`) directly into the applications.

---

## User Scenarios & Testing

### User Story 1 - Unified Ingress & Perimeter Forward-Auth (Priority: P1)

As a cluster operator, I want unauthenticated requests to protected endpoints to be evaluated by Authentik via Envoy Gateway's `extAuth` filter across a single ingress Gateway, so that I can retire multi-Gateway sprawl, reclaim LoadBalancer IPs, and rely on Authentik's native login and error interfaces.

**Why this priority**: Core security boundary and replacement of current fragile Envoy OIDC mechanics. Eliminates dedicated Gateways and custom error-page apps.

**Independent Test**: Can be tested by visiting a forward-auth protected app (e.g., `https://herdr.${SECRET_DOMAIN}`) unauthenticated, confirming an automatic redirect to Authentik's login page, signing in, and confirming immediate access to the app without touching app-level code.

**Acceptance Scenarios**:

1. **Given** an unauthenticated user visits a protected URL (e.g., `https://paseo.${SECRET_DOMAIN}`), **When** Envoy Gateway receives the request, **Then** it delegates authorization to Authentik Outpost via `extAuth` and redirects the user to `https://auth.${SECRET_DOMAIN}`.
2. **Given** an authenticated user who is not in the required group attempts to access an admin-restricted app, **When** Authentik evaluates the policy, **Then** it presents Authentik's built-in access-denied page indicating permission failure, with no redirect loops.
3. **Given** an authenticated user in the required group visits the app, **When** Authentik approves the request, **Then** Envoy Gateway forwards the request along with identity headers (`X-authentik-username`, `X-authentik-email`).

---

### User Story 2 - True SSO for Native Applications (Priority: P2)

As an application user and operator, I want cluster services that natively support OIDC (such as Grafana and ArgoCD) to authenticate directly against Authentik as an identity provider, so that local application passwords are eliminated and role assignments (Admin vs Viewer) are synchronized from Authentik groups automatically.

**Why this priority**: Eliminates the "Double Login" problem (authenticating at the proxy, then needing a local app password) and centralizes RBAC.

**Independent Test**: Can be tested by visiting Grafana (`https://grafana.${SECRET_DOMAIN}`), clicking "Sign in with Authentik" (or auto-logging in), and verifying that an admin user is granted Grafana `Admin` organization role while a general user receives Grafana `Viewer`.

**Acceptance Scenarios**:

1. **Given** Grafana is configured with Authentik Generic OAuth, **When** an authorized user logs in, **Then** their Grafana account is automatically provisioned, their profile email is populated, and their role matches their Authentik group membership (`cluster-admins` $\to$ Admin, `cluster-users` $\to$ Viewer).
2. **Given** ArgoCD is configured with Authentik OIDC, **When** a user in the `cluster-admins` group logs into ArgoCD, **Then** ArgoCD RBAC recognizes the group claim and grants full administrative access without using the bootstrap `admin` password.
3. **Given** a user is removed from `cluster-admins` in Authentik, **When** they log into Grafana or ArgoCD, **Then** their administrative privileges are automatically revoked on the next token refresh.

---

### User Story 3 - Upstream Google Federation & Passwordless Login (Priority: P3)

As a cluster user, I want to sign into Authentik using my existing Google account or modern WebAuthn / Passkeys, so that I do not need to memorize new master credentials for the cluster while the cluster operator maintains strict control over approved accounts.

**Why this priority**: Preserves the convenience of Google SSO while layering Authentik's fine-grained group authorization and optional hardware-key MFA on top.

**Independent Test**: Can be tested by clicking "Sign in with Google" on Authentik's login page, completing Google OIDC authentication, and confirming that approved email accounts are automatically bound to cluster groups.

**Acceptance Scenarios**:

1. **Given** Google is configured as an upstream OAuth source in Authentik, **When** a user clicks "Sign in with Google", **Then** they are redirected to Google accounts and returned to Authentik upon consent.
2. **Given** an approved Google email logs in for the first time, **When** enrollment flows run, **Then** Authentik provisions their user profile and assigns default group memberships based on declarative email rules.
3. **Given** an unapproved Google email attempts login, **When** Authentik evaluates the enrollment policy, **Then** access is denied with a clear message and no account is activated.

---

### User Story 4 - User Dashboard & Self-Service Portal (Priority: P4)

As a cluster user, I want an application dashboard (`https://auth.${SECRET_DOMAIN}`) displaying icons for all services I have access to, so that I have a single bookmark for the entire homelab and can manage my own active sessions and Passkeys.

**Why this priority**: Improves user experience and provides visibility into available apps based on current permissions.

**Independent Test**: Can be tested by logging into `https://auth.${SECRET_DOMAIN}`, verifying that visible application cards match the user's group permissions, and launching an app directly from the portal.

**Acceptance Scenarios**:

1. **Given** a user in `cluster-users` logs into the Authentik portal, **When** viewing the dashboard, **Then** only user-accessible services (e.g. Grafana) are displayed; admin-only services are hidden or marked restricted.
2. **Given** a user navigates to their user settings, **When** they register a Passkey (TouchID / YubiKey), **Then** future logins allow passwordless biometric authentication.
3. **Given** a user clicks "Log out" in the portal, **When** sign-out executes, **Then** sessions across Authentik and forward-auth services are invalidated.

---

### User Story 5 - Retire Legacy OAuth Gateways & Custom Plumbing (Priority: P5)

As a cluster operator, I want to completely remove legacy OAuth Gateways, custom NGINX error pages, and low-level Envoy patches, so that ingress infrastructure is standard, maintainable, and clean.

**Why this priority**: Eliminates technical debt and frees allocated network resources.

**Independent Test**: Can be tested by deleting `kubernetes/workloads/apps/oauth-pages/`, `oauth-header-limits.yaml`, and the dedicated OAuth Gateways, and confirming that all applications remain fully accessible through `envoy-external`.

**Acceptance Scenarios**:

1. **Given** Authentik forward-auth is active, **When** the `oauth-pages` deployment, ConfigMap, and route rewrites are deleted, **Then** no authentication or error behavior degrades.
2. **Given** `envoy-oauth-admin`, `envoy-oauth-users`, and `envoy-oauth-internal` Gateways are removed, **When** inspecting cluster LoadBalancer IPs, **Then** IPs `192.168.1.149`, `192.168.1.150`, and `192.168.1.151` are released.
3. **Given** Cloudflare Tunnel is updated, **When** explicit app routes are removed from `cloudflare-tunnel`'s `config.yaml`, **Then** the wildcard rule `*.${SECRET_DOMAIN}` successfully routes all traffic to `envoy-external`.

---

## Edge Cases

- **Authentik Outage / Fail-Closed**: If Authentik server or outpost pods crash, Envoy Gateway's `extAuth` policy must fail closed, preventing unauthenticated access to backend services.
- **Database Backup & Recovery**: Authentik requires PostgreSQL and Redis. Loss of database state without backups would lose user-group bindings; persistent volumes and automated database backups (e.g., via CloudNativePG or local volume backups) must be maintained.
- **Session Expiry on Upstream Apps**: Applications with native OIDC (ArgoCD, Grafana) have independent session lifetimes. Authentik refresh tokens must renew sessions silently without forcing frequent interactive logins.
- **Direct LAN vs Cloudflare WAN Ingress**: Internal access via LAN Gateway (`envoy-internal`) or Tailscale can be assigned tailored Authentik policies (e.g., bypass MFA on trusted subnets, require MFA externally).

---

## Requirements

### Functional Requirements

- **FR-001**: Authentik MUST be deployed in the `security` (or `network`) namespace using the official Helm chart or Kustomize manifests, backed by PostgreSQL and Redis.
- **FR-002**: Authentik MUST configure an upstream Google OAuth Source allowing users to authenticate via Google OIDC.
- **FR-003**: Authentik MUST provide an embedded or managed Outpost supporting Envoy `ext_authz` (HTTP or gRPC) for forward authentication.
- **FR-004**: Envoy Gateway MUST enforce authentication on protected `HTTPRoutes` via `SecurityPolicy.spec.extAuth` referencing the Authentik Outpost service.
- **FR-005**: All external traffic MUST enter through a single unified Gateway (`envoy-external`), retiring `envoy-oauth-admin`, `envoy-oauth-users`, and `envoy-oauth-internal`.
- **FR-006**: Cloudflare Tunnel configuration MUST route `auth.${SECRET_DOMAIN}` and wildcard `*.${SECRET_DOMAIN}` directly to `envoy-external`.
- **FR-007**: Grafana MUST be configured with Generic OAuth pointing to Authentik's OIDC endpoint, enabling auto-login and mapping Authentik groups to Grafana `Admin` and `Viewer` roles.
- **FR-008**: ArgoCD MUST be configured with OIDC pointing to Authentik, eliminating local admin credentials and mapping Authentik `cluster-admins` to ArgoCD `role:admin`.
- **FR-009**: Authentik MUST maintain at minimum two core groups:
  - `cluster-admins`: Access to all services, full administrative rights in ArgoCD and Grafana.
  - `cluster-users`: Access to user-tier services (e.g. Grafana Viewer).
- **FR-010**: The custom static NGINX application `oauth-pages`, its HTML ConfigMaps (`denied.html`, `logged-out.html`), and its security policies MUST be completely removed.
- **FR-011**: The low-level `EnvoyPatchPolicy` JSON patches in `oauth-header-limits.yaml` MUST be removed.
- **FR-012**: Authentik configuration (Applications, Providers, Groups, and Flows) SHOULD be declared using Authentik Blueprints or OpenTofu/Terraform to ensure GitOps reproducibility.
- **FR-013**: Authentik database credentials, secret keys, and Google OAuth client secrets MUST be stored encrypted via 1Password `ExternalSecret` or SOPS.

---

### Key Entities

- **Authentik Core**: The web server and background worker running Authentik logic, managing flows, users, tokens, and database models.
- **Authentik Outpost**: The reverse-proxy / forward-auth worker that interfaces directly with Envoy Gateway's `extAuth` filter.
- **Upstream Source**: Google OAuth credentials used by Authentik to authenticate incoming users.
- **Downstream Providers**:
  - *Proxy Provider*: Forward-auth endpoints for apps without native auth (Paseo, Herdr, OpenClaw).
  - *OAuth2/OIDC Provider*: Native token issuers for apps with built-in SSO (Grafana, ArgoCD).
- **Group Mappings**: Declarative associations between Authentik groups (`cluster-admins`, `cluster-users`) and application-specific RBAC roles.
- **Unified Gateway (`envoy-external`)**: The single ingress entrypoint handling TLS and routing.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% of unauthenticated requests to protected perimeter apps redirect to Authentik login; zero direct bypasses exist.
- **SC-002**: Users can log into Grafana and ArgoCD via SSO without entering a local username or password.
- **SC-003**: Adding or removing a user from `cluster-admins` in Authentik updates their permissions across Grafana, ArgoCD, and perimeter apps simultaneously without modifying Kubernetes manifests.
- **SC-004**: Total ingress Gateways are reduced from five to two (`envoy-external` and `envoy-internal`).
- **SC-005**: Three MetalLB/Cilium IPAM addresses (`192.168.1.149`, `.150`, `.151`) are released back to the pool.
- **SC-006**: Custom error-page NGINX deployment (`oauth-pages`) and Envoy JSON patches (`oauth-header-limits.yaml`) are fully eliminated.
- **SC-007**: Authentik user portal is accessible at `https://auth.${SECRET_DOMAIN}` displaying authorized application shortcuts.
