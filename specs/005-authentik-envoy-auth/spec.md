# Feature Specification: Authentik Cluster Authentication

**Feature Branch**: `005-authentik-envoy-auth`
**Created**: 2026-03-03
**Status**: Draft
**Input**: User description: "Implement Authentik Auth on the Cluster, integrate it with Envoy Gateway. Make an alternative to Google OIDC/SSO with Google via Proxy"

## Clarifications

### Session 2026-03-03

- Q: What should this feature's required migration scope be for protected routes? → A: Require phased rollout: migrate only a defined subset of routes first, keep others on Google-proxy.
- Q: How long should authentication outcome records be required to remain queryable? → A: 30 days.
- Q: If a protected route is missing explicit auth-path assignment, what should happen? → A: Deny access and return configuration error response.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Stand up Authentik and access protected apps (Priority: P1)

As a platform administrator, I can deploy Authentik in the cluster and then allow cluster users to sign in through Authentik to reach protected applications routed through the cluster gateway.

**Why this priority**: This delivers the core value of introducing Authentik-based authentication and enabling secure app access.

**Independent Test**: Can be fully tested by attempting to open a protected application while unauthenticated, completing sign-in through Authentik, and confirming access is granted.

**Acceptance Scenarios**:

1. **Given** a user is not signed in and opens a protected application URL, **When** the request reaches the gateway, **Then** the user is prompted to authenticate through Authentik.
2. **Given** a user successfully signs in through Authentik, **When** they return to the requested application URL, **Then** the gateway allows access without an additional login prompt.
3. **Given** Authentik is not yet deployed, **When** administrators apply this feature's declarative manifests, **Then** Authentik becomes available as an authentication provider for protected routes.
4. **Given** required Authentik bootstrap secrets are missing, **When** reconciliation runs, **Then** deployment fails with an explicit operator-visible error and protected routes are not exposed without authentication.

______________________________________________________________________

### User Story 2 - Keep Google SSO alternative available (Priority: P2)

As a platform administrator, I can keep Google-based SSO available as an alternative path while Authentik is introduced.

**Why this priority**: This minimizes rollout risk and preserves continuity for users and apps that still rely on Google SSO.

**Independent Test**: Can be fully tested by confirming at least one protected route authenticates through Authentik and at least one protected route remains functional through the Google-based proxy path.

**Acceptance Scenarios**:

1. **Given** both authentication paths are configured, **When** users access routes assigned to each path, **Then** each route enforces its assigned sign-in method without cross-routing failures.
2. **Given** Google SSO is still required for selected services, **When** users access those services, **Then** authentication continues to complete successfully through the Google-based proxy path.

______________________________________________________________________

### User Story 3 - Operate and audit auth behavior (Priority: P3)

As a platform administrator, I can verify which authentication path is applied and review authentication outcomes for troubleshooting.

**Why this priority**: Operational visibility is needed to support migration and quickly resolve sign-in or routing issues.

**Independent Test**: Can be fully tested by reviewing authentication outcome records for successful and denied requests across both auth paths and confirming the applied policy is identifiable.

**Acceptance Scenarios**:

1. **Given** an authentication attempt succeeds or fails, **When** administrators inspect platform records, **Then** they can identify outcome, timestamp, target route, and auth path used.

______________________________________________________________________

### Edge Cases

- What happens when Authentik is temporarily unavailable during a user sign-in attempt?
- If a protected route is missing explicit auth-path assignment, access is denied and a configuration error response is returned.
- What happens when a user has an active session in one auth path but not the other?
- What happens when required Authentik bootstrap secrets are missing at deployment time?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The cluster gateway MUST support authentication via Authentik for protected application routes.
- **FR-002**: Unauthenticated requests to Authentik-protected routes MUST be challenged for sign-in before application access is granted.
- **FR-003**: After successful Authentik sign-in, users MUST be returned to their originally requested protected route.
- **FR-004**: The platform MUST preserve Google-based SSO via proxy as an alternative authentication path during Authentik rollout.
- **FR-005**: Each protected route MUST be explicitly assigned to one authentication path (Authentik or Google-proxy) to avoid ambiguous behavior.
- **FR-006**: If the assigned authentication service for a route is unavailable, users MUST receive a clear access failure response and no unsecured fallback access.
- **FR-007**: The platform MUST provide route-level records of authentication outcomes, including success and denial events.
- **FR-008**: Administrators MUST be able to identify which authentication path is applied to each protected route.
- **FR-009**: Existing protected routes that are not explicitly migrated to Authentik MUST continue to function with their current Google-proxy authentication behavior.
- **FR-010**: This feature MUST define and migrate an initial subset of protected routes to Authentik, while non-selected routes remain on Google-proxy during the same release window.
- **FR-011**: Authentication outcome records MUST remain queryable for at least 30 days.
- **FR-012**: Requests for protected routes with missing auth-path assignment MUST be denied with a configuration error response.
- **FR-013**: The platform MUST deploy and configure Authentik in-cluster using declarative Git-managed resources as part of this feature.
- **FR-014**: Authentik deployment MUST fail safely when required bootstrap secrets are missing, with clear operator-visible failure signals.

### Key Entities *(include if feature involves data)*

- **Protected Route**: A publicly reachable application entry point with attributes for host/path scope and assigned authentication path.
- **Authentication Path**: A sign-in option used by the gateway (Authentik or Google-proxy) with state indicating availability and assignment usage.
- **Authentication Outcome Record**: An auditable event containing route identifier, authentication path, user outcome (allowed/denied), and timestamp.
- **Authentik Deployment**: In-cluster identity provider deployment with attributes for namespace, release state, and required bootstrap secret references.

## Assumptions

- Google-based SSO must remain available during initial rollout as a fallback and migration path.
- Route-level assignment is the unit of control for selecting Authentik vs Google-proxy behavior.
- Authentication identity and session lifecycle policy continue to follow existing cluster standards unless explicitly changed in a later feature.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of routes designated for Authentik require authentication before access is granted.
- **SC-002**: At least 95% of successful sign-ins on Authentik-protected routes complete and return users to the requested destination in under 30 seconds under normal operating conditions.
- **SC-003**: 100% of routes designated to remain on Google-proxy authentication continue to pass their existing sign-in flow after rollout.
- **SC-004**: For authentication failures, administrators can determine route, auth path, and outcome from records within 5 minutes for at least 95% of investigated incidents.
- **SC-005**: In environments with complete required secrets, Authentik deployment reaches ready state through the GitOps workflow without manual cluster-side configuration.
