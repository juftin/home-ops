# Feature Specification: Envoy Gateway OIDC with Google OAuth

**Feature Branch**: `003-envoy-gateway-oidc`
**Created**: 2026-02-21
**Status**: Draft
**Input**: User description: "Implement Envoy Gateway OIDC with Google OAuth. I should be able to maintain separate Google Email Whitelists (Encrypted) and easily put a given application behind OAuth. Not all applications will go behind OAuth."

## Clarifications

### Session 2026-02-21

- Q: What is the opt-in mechanism for placing an app behind OAuth, and how are different email whitelists supported? → A: Multiple Gateways — one public Gateway (no auth) and one or more OAuth Gateways each with a Gateway-level SecurityPolicy and its own encrypted email whitelist; operators opt an app in by attaching its HTTPRoute to the appropriate OAuth Gateway; different whitelists = different Gateways.
- Q: What do non-whitelisted users see after completing Google login? → A: Custom error page — a styled "access denied" page hosted as a cluster resource, explaining the user is not authorized.
- Q: Should email address comparison be case-sensitive or case-insensitive? → A: Case-insensitive — email comparison always normalizes to lowercase; whitelist entries may be stored in any case.
- Q: What observability is required for auth events? → A: Gateway access logs only — auth events (success, denial, redirect) are captured in Envoy Gateway's standard access logs; no additional observability infrastructure required.
- Q: Where are users redirected after logging out of an OAuth-protected app? → A: Dedicated logout confirmation page — a simple static "you've been logged out" page hosted as a cluster resource; no immediate re-login (no root page exists to redirect to).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Protect an Application with Google OAuth (Priority: P1)

As the cluster operator, I want to opt a specific application into Google OAuth protection so that only
approved Google account holders can access it. Enabling protection requires only pointing the app's
HTTPRoute at an OAuth-enabled Gateway — no per-app security policy configuration is needed. Apps not
requiring protection continue to use the public Gateway unchanged.

**Why this priority**: This is the core deliverable — without the ability to selectively protect apps,
the feature has no value.

**Independent Test**: Can be fully tested by placing one application behind an OAuth Gateway, verifying
that unauthenticated browser visits redirect to Google's login page, and that a whitelisted user can
complete login and reach the application.

**Acceptance Scenarios**:

1. **Given** an application's HTTPRoute is attached to a public Gateway, **When** the operator
   re-attaches it to an OAuth Gateway, **Then** subsequent unauthenticated visits redirect to Google's
   login flow with no other configuration changes required.
2. **Given** an HTTPRoute is attached to an OAuth Gateway, **When** a user who is on that Gateway's
   email whitelist completes Google login, **Then** they are redirected back to the application and
   can access it normally.
3. **Given** a second application's HTTPRoute remains attached to the public Gateway, **When** a user
   visits it, **Then** it is accessible without any authentication challenge.

______________________________________________________________________

### User Story 2 - Enforce Email Whitelist (Priority: P2)

As the cluster operator, I want only specific Google accounts (identified by email address) to be
allowed access to protected applications, so that even valid Google account holders outside my approved
list are denied entry.

**Why this priority**: Protecting an app with Google login alone is insufficient — without an email
allowlist, any Google account could gain access. This is the access-control complement to Story 1.

**Independent Test**: Can be fully tested by verifying that a Google account NOT on the whitelist
receives an access-denied response after completing a valid Google login, while a whitelisted account
proceeds normally.

**Acceptance Scenarios**:

1. **Given** an application is OAuth-protected with a configured email whitelist, **When** a user
   authenticates with a Google account whose email is on the whitelist, **Then** access is granted.
2. **Given** an application is OAuth-protected, **When** a user authenticates with a Google account
   whose email is NOT on the whitelist, **Then** they are shown a custom "access denied" error page
   explaining they are not authorized — they are not looped back to Google login.
3. **Given** the email whitelist is empty or undefined, **When** any user authenticates, **Then** access
   is denied (fail-closed behavior).

______________________________________________________________________

### User Story 3 - Manage Email Whitelists as Encrypted Secrets (Priority: P3)

As the cluster operator, I want to store email whitelists as encrypted secrets in the GitOps repository
so that approved email addresses are version-controlled but never committed in plaintext.

**Why this priority**: Security hygiene — email addresses are PII and the whitelist is the access
control boundary; it must be encrypted at rest in Git.

**Independent Test**: Can be fully tested by verifying that the email whitelist file in the repository
is SOPS-encrypted, that decryption in-cluster produces the correct list, and that modifying the list
(re-encrypting and committing) takes effect after Flux reconciles.

**Acceptance Scenarios**:

1. **Given** the operator updates the encrypted email whitelist and commits it, **When** Flux reconciles,
   **Then** the updated list is active without any manual in-cluster steps.
2. **Given** the repository is cloned fresh, **When** the whitelist file is inspected, **Then** email
   addresses are not visible in plaintext.
3. **Given** different applications need different whitelists, **When** each has its own encrypted
   whitelist secret, **Then** they operate independently without cross-contamination.

______________________________________________________________________

### User Story 4 - Multiple OAuth Gateways with Independent Whitelists (Priority: P4)

As the cluster operator, I want to maintain multiple OAuth Gateways each with its own email whitelist,
so I can group applications by access level (e.g., admin-only vs. family-accessible) without
duplicating OIDC configuration or creating per-app policies.

**Why this priority**: Operational scalability — a single shared whitelist across all protected apps
is too coarse; per-app policies are too granular; Gateway-grouped whitelists hit the right balance.

**Independent Test**: Can be tested by configuring two OAuth Gateways with distinct whitelists, attaching
different apps to each, and verifying that a user on whitelist A can access Gateway-A apps but is denied
on Gateway-B apps, and vice versa.

**Acceptance Scenarios**:

1. **Given** two OAuth Gateways exist with different whitelists, **When** a user on whitelist A logs
   in via a Gateway-A app, **Then** they can access all Gateway-A apps but are denied on Gateway-B apps.
2. **Given** a new application needs to be accessible to whitelist-B users, **When** the operator
   attaches its HTTPRoute to Gateway B, **Then** whitelist-B users can access it with zero changes to
   the whitelist or Gateway B's SecurityPolicy.

______________________________________________________________________

### Edge Cases

- What happens when a user's Google session token expires mid-use? → They should be silently
  re-authenticated via the refresh token flow, or prompted to log in again without losing their
  destination URL.
- What happens if a whitelist entry and the Google token email differ only in case (e.g.,
  `User@Gmail.com` vs `user@gmail.com`)? → The entry will not match. Envoy Gateway does exact
  string matching; Google always returns lowercase emails. Whitelist entries must be stored in
  lowercase by convention — mixed-case entries silently fail to match.
- What happens when the email whitelist secret is deleted or malformed? → The protected application
  should fail closed — all access is denied until the secret is restored.
- What happens when a user is removed from the whitelist while they have an active session? → Their
  current session remains valid until the session/cookie expires; they will be denied on the next
  full authentication cycle.
- What happens when the Google OAuth provider is unreachable? → Unauthenticated requests to protected
  apps are blocked; applications without OAuth opt-in continue to function normally.
- What happens when the operator removes the OAuth opt-in from an application? → The application
  immediately becomes publicly accessible again without requiring a restart.
- What happens when a user visits the logout path? → Their session cookies are cleared and they are
  shown a static "logged out" confirmation page; since no root page exists, they are not automatically
  redirected back to any app or login flow.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide one or more OAuth-enabled Gateways, each with a Gateway-level
  OIDC SecurityPolicy and its own encrypted email whitelist; operators opt an application in by
  attaching its HTTPRoute to the appropriate OAuth Gateway.
- **FR-002**: Each OAuth Gateway MUST have exactly one redirect URL (e.g.,
  `https://gateway.example.com/oauth2/callback`) pre-registered in Google Console; all apps on that
  Gateway share this callback URL.
- **FR-003**: The system MUST enforce an email-based allowlist after successful Google authentication,
  denying access to accounts not on the list; denied users MUST be shown a custom "access denied"
  error page (hosted as a cluster resource) explaining they are not authorized.
- **FR-012**: The system MUST host a custom access-denied error page as a cluster resource; this page
  is displayed to any authenticated Google user whose email is not on the relevant Gateway's whitelist.
- **FR-013**: All email whitelist entries MUST be stored in lowercase. Google's OIDC token always
  returns the `email` claim in lowercase; whitelist entries stored in any other case will not match
  and will result in access denial. Enforcement is by operator convention, not runtime normalization
  (Envoy Gateway's JWT claim authorization uses exact string matching).
- **FR-016**: The SecurityPolicy authorization MUST additionally enforce `email_verified: true` as
  a required JWT claim alongside the email allowlist check; accounts with unverified email addresses
  are denied regardless of whether their email appears on the whitelist.
- **FR-004**: Each email whitelist MUST be stored as a SOPS-encrypted secret in the GitOps repository
  and decrypted automatically in-cluster.
- **FR-005**: The system MUST support multiple independent email whitelists by providing multiple
  OAuth Gateways, each with its own whitelist secret; apps are grouped by access level via Gateway
  selection.
- **FR-006**: All applications attached to the same OAuth Gateway MUST share that Gateway's email
  whitelist and session cookie, enabling single-login access across all apps in that group.
- **FR-007**: A public Gateway with no SecurityPolicy MUST exist for applications that require no
  authentication; HTTPRoutes on this Gateway MUST remain accessible without any auth challenge.
- **FR-008**: The system MUST fail closed — if the whitelist secret is missing or unreadable, access
  to the protected application is denied.
- **FR-009**: The OAuth configuration (client credentials) MUST be stored as an encrypted secret and
  never committed in plaintext.
- **FR-010**: Enabling or disabling OAuth protection for an application MUST be achievable through a
  GitOps-managed configuration change with no manual in-cluster steps beyond Flux reconciliation.
- **FR-011**: Users MUST be redirected back to their originally requested URL after successful
  authentication.
- **FR-014**: Auth event observability MUST rely solely on Envoy Gateway's built-in access logs;
  all authentication events (successful logins, denied access, token redirects) are captured there
  with no additional logging infrastructure required.
- **FR-015**: Each OAuth Gateway MUST expose a logout path (e.g., `/logout`) that clears session
  cookies and redirects the user to a dedicated static "logged out" confirmation page hosted as a
  cluster resource; no automatic re-login is triggered after logout.

### Key Entities

- **OIDC Provider Configuration**: Shared Google OAuth credentials (client ID, client secret, issuer
  URL) used cluster-wide; stored encrypted; referenced by each OAuth Gateway's SecurityPolicy.
- **Email Whitelist**: A list of approved Google email addresses scoped to a single OAuth Gateway;
  stored as a SOPS-encrypted secret; one whitelist per OAuth Gateway; multiple whitelists supported
  by running multiple OAuth Gateways.
- **OAuth Gateway**: A Gateway with a Gateway-level SecurityPolicy enforcing OIDC authentication
  against its email whitelist; has one pre-registered redirect URL in Google Console; all HTTPRoutes
  attached to this Gateway are protected; session cookies are shared across all apps on the same
  Gateway via a shared cookie domain.
- **Public Gateway**: A Gateway with no SecurityPolicy; HTTPRoutes attached here require no
  authentication.
- **User Session**: A browser-scoped session established after successful OIDC authentication on an
  OAuth Gateway; shared across all apps on that Gateway via a shared cookie domain; contains identity
  claims (email) used for whitelist enforcement; has a configurable lifetime.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can enable Google OAuth protection for an application by making a single
  targeted configuration change, with no changes required to unprotected applications.
- **SC-002**: 100% of unauthenticated requests to OAuth-protected applications are redirected to
  Google login — zero direct access bypasses.
- **SC-003**: 100% of authenticated requests from Google accounts not on the whitelist result in
  access denial — no unauthorized access is granted.
- **SC-004**: No email addresses or OAuth credentials appear in plaintext anywhere in the Git
  repository.
- **SC-005**: An email whitelist update committed to the repository takes effect across all
  referencing applications within one Flux reconciliation cycle (default: under 10 minutes) with no
  manual intervention.
- **SC-006**: Applications without an OAuth opt-in experience zero authentication overhead — response
  times and availability are unaffected by the OIDC infrastructure.
- **SC-007**: A new application can be placed behind OAuth by attaching its HTTPRoute to an existing
  OAuth Gateway, requiring zero changes to that Gateway's SecurityPolicy or email whitelist.
- **SC-008**: After a user logs out, they land on a static confirmation page with no automatic
  redirect to Google login; subsequent visits to protected apps require a fresh authentication.

## Assumptions

- Google is the sole OIDC provider for this feature; multi-provider support is out of scope.
- The OIDC configuration requests at minimum the `openid email` scopes so that the `email` and
  `email_verified` claims are present in Google's ID token; scope configuration is part of the
  SecurityPolicy OIDC spec and managed by the operator.
- All applications are exposed via Envoy Gateway; apps using other ingress paths are out of scope.
- The cluster operates multiple named Gateways: at least one public Gateway and one or more OAuth
  Gateways; the number and names of OAuth Gateways are determined by the operator based on desired
  access groupings (e.g., "admin", "family").
- Each OAuth Gateway uses one Google OAuth client (client ID/secret) with one pre-registered redirect
  URL; a single Google OAuth application can register multiple redirect URLs (one per OAuth Gateway).
- Session lifetime defaults to 1 hour with silent refresh via refresh tokens; configurable per
  Gateway if needed.
- The operator (cluster admin) is the only person who manages whitelists; there is no self-service
  user enrollment UI in scope.
- Envoy Gateway's native OIDC/SecurityPolicy capability is the enforcement mechanism; no additional
  sidecar proxies are introduced.
- Cookie domain is set to the cluster's shared root domain on each OAuth Gateway so session cookies
  are shared across all apps under that Gateway's subdomain.
