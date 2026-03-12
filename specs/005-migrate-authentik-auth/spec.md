# Feature Specification: Envoy Authentik Authentication Migration

**Feature Branch**: `005-migrate-authentik-auth`
**Created**: 2026-03-01
**Status**: Draft
**Input**: User description: "Objective: Replace direct Google OAuth within Envoy Gateway with Authentik. Authentik acts as the centralized Identity Provider. The setup must remain interchangeable with the legacy authentication method. Future management will transition to Terraform. Current State: Envoy Gateway handles direct Google OAuth authentication using a SecurityPolicy. Cilium manages cluster networking. Target State: Envoy Gateway forwards authentication requests to Authentik via extAuth. Authentik handles Google OAuth login, group assignment, and policy enforcement, then returns authorization success to Envoy Gateway."

## Clarifications

### Session 2026-03-01

- Q: What minimum fields must every authentication outcome record include? → A: timestamp, user identity, route, decision, denial reason.
- Q: What service availability target should this feature meet for protected-route authentication? → A: Best effort (no numeric target).
- Q: Should mode switching apply to all protected routes at once, or allow partial rollout by route/namespace? → A: Global mode switch for all protected routes simultaneously.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Centralized authentication flow (Priority: P1)

As a platform operator, I need Envoy Gateway to delegate authentication decisions to Authentik so that user login, group mapping, and access decisions are managed in one identity control point.

**Why this priority**: This is the core business outcome of the migration and unlocks centralized policy governance.

**Independent Test**: Can be fully tested by attempting to access a protected route and validating that authentication and authorization are completed by Authentik before access is granted.

**Acceptance Scenarios**:

1. **Given** a protected route and a valid user identity, **When** the user signs in through the identity flow, **Then** Authentik returns an allow decision and Envoy Gateway grants access.
2. **Given** a protected route and a user without required group membership, **When** the user authenticates, **Then** Authentik returns a deny decision and Envoy Gateway blocks access.

______________________________________________________________________

### User Story 2 - Interchangeable auth mode (Priority: P2)

As a platform operator, I need authentication mode to be switchable between Authentik-based and legacy direct OAuth so that rollback and transitional operations remain safe.

**Why this priority**: Interchangeability reduces migration risk and supports controlled rollout.

**Independent Test**: Can be tested by switching auth mode and confirming protected routes enforce whichever mode is currently active without route-level breakage.

**Acceptance Scenarios**:

1. **Given** the cluster is configured for Authentik mode, **When** an operator switches to legacy mode, **Then** protected routes continue requiring authentication via legacy behavior.
2. **Given** the cluster is configured for legacy mode, **When** an operator switches back to Authentik mode, **Then** protected routes enforce Authentik-based authentication and authorization.

______________________________________________________________________

### User Story 3 - Operational continuity and auditability (Priority: P3)

As a security operator, I need clear authentication outcomes and policy enforcement visibility so that access incidents can be investigated quickly.

**Why this priority**: Operational confidence and troubleshooting speed are necessary for production readiness.

**Independent Test**: Can be tested by generating allow and deny events and verifying operators can identify outcome, subject, and policy context for each protected access attempt.

**Acceptance Scenarios**:

1. **Given** a mix of successful and denied protected requests, **When** operators review authentication outcomes, **Then** they can distinguish outcome reason and affected identity for each request.

______________________________________________________________________

### Edge Cases

- What happens when Authentik is temporarily unavailable during a protected request? Access must fail closed, and operators must receive a clear failure signal.
- How does system handle users who authenticate successfully but have no mapped groups? Access must be denied for routes requiring group-based authorization.
- What happens when configuration is set to legacy mode but Authentik settings remain present? Only the selected mode should be enforced.
- What happens during in-flight mode transitions? New requests must follow the newly active mode without partially applying both modes.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST delegate protected-route authentication and authorization decisions to Authentik when Authentik mode is enabled.
- **FR-002**: System MUST preserve a legacy authentication mode that can be re-enabled without redefining protected-route intent.
- **FR-003**: Operators MUST be able to switch authentication mode between Authentik and legacy using a single explicit cluster-wide mode selection that applies to all protected routes simultaneously.
- **FR-004**: System MUST enforce group-based authorization outcomes returned by Authentik for protected routes.
- **FR-005**: System MUST deny access when an authentication decision cannot be obtained for a protected route.
- **FR-006**: System MUST produce observable authentication outcomes for allow and deny decisions, including timestamp, identity subject, protected route, decision outcome, and denial reason for denied requests.
- **FR-007**: System MUST keep authentication behavior consistent across protected routes during and after mode transitions.
- **FR-008**: System MUST support a configuration model that can be managed by current workflows now and transitioned to Terraform ownership later without changing expected authentication behavior.

### Key Entities *(include if feature involves data)*

- **Authentication Mode**: The active policy selector that determines whether protected routes use Authentik-based or legacy authentication behavior.
- **Protected Route**: Any ingress path requiring identity validation and authorization before access is granted.
- **Identity Subject**: The authenticated user principal evaluated for access decisions.
- **Authorization Group**: Group membership signal used to determine whether an authenticated subject is allowed on a protected route.
- **Authorization Decision**: Allow or deny result returned for a protected request, including reason context.

## Assumptions

- Formal availability SLO commitments are out of scope for this phase; reliability is managed as best effort.
- Existing protected routes and security intent remain in scope; this feature changes authentication control flow rather than route inventory.
- Legacy mode remains available only for transition and rollback, not as a long-term primary model.
- Identity providers used behind Authentik can evolve over time as long as Authentik returns compatible authorization decisions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of protected-route access attempts are evaluated by the currently selected authentication mode.
- **SC-002**: Operators can complete a cluster-wide switch between Authentik and legacy modes with no unplanned protected-route outages during the change window.
- **SC-003**: At least 95% of authentication-related incident investigations can determine user, decision outcome, and denial reason within 10 minutes.
- **SC-004**: Unauthorized users lacking required group membership are denied access on 100% of tested protected-route attempts.
