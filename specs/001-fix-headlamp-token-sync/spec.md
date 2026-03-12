# Feature Specification: Headlamp Token Sync Reliability

**Feature Branch**: `[001-fix-headlamp-token-sync]`
**Created**: 2026-03-12
**Status**: Draft
**Input**: User description: "HeadLamp's token does not stay in sync with the 1Password secret. Either the secret isn't up to date or the Envoy OAuth via Google is overriding the right tokens."

## User Scenarios & Testing *(mandatory)*

<!--
  IMPORTANT: User stories should be PRIORITIZED as user journeys ordered by importance.
  Each user story/journey must be INDEPENDENTLY TESTABLE - meaning if you implement just ONE of them,
  you should still have a viable MVP (Minimum Viable Product) that delivers value.

  Assign priorities (P1, P2, P3, etc.) to each story, where P1 is the most critical.
  Think of each story as a standalone slice of functionality that can be:
  - Developed independently
  - Tested independently
  - Deployed independently
  - Demonstrated to users independently
-->

### User Story 1 - Keep login access aligned with current secret (Priority: P1)

As a homelab operator, I need Headlamp authentication to consistently use the currently approved token value so that authorized users can sign in without intermittent failures.

**Why this priority**: Authentication breakage blocks core platform visibility and operations, making this the most urgent user-facing reliability issue.

**Independent Test**: Rotate the active secret value and verify that a new login uses the updated token and succeeds without manual intervention.

**Acceptance Scenarios**:

1. **Given** an active token secret, **When** a user starts a new Headlamp login, **Then** the authentication decision is made against the current active secret value.
2. **Given** the token secret has been rotated, **When** a user starts a new login after propagation, **Then** login succeeds with the rotated secret and the prior value is no longer accepted.

______________________________________________________________________

### User Story 2 - Resolve token-source conflicts predictably (Priority: P2)

As a homelab operator, I need predictable behavior when token values conflict across sources so I can quickly diagnose and correct access problems.

**Why this priority**: Intermittent failures are often caused by competing token sources; deterministic handling reduces ambiguity and recovery time.

**Independent Test**: Introduce a deliberate mismatch between token sources and verify the system applies a documented precedence rule and records a clear incident reason.

**Acceptance Scenarios**:

1. **Given** conflicting token values are detected, **When** a login attempt occurs, **Then** the system applies a single authoritative source rule and logs the decision context.
2. **Given** a conflict has been resolved, **When** the next login attempt occurs, **Then** authentication succeeds with the authoritative current value.

______________________________________________________________________

### User Story 3 - Provide operational visibility for token sync health (Priority: P3)

As a homelab operator, I need clear visibility into token sync status and recent auth decisions so I can detect drift before users report outages.

**Why this priority**: Visibility does not directly restore access, but it prevents repeated outages and reduces troubleshooting effort.

**Independent Test**: Review status and event history after normal operation, secret rotation, and conflict conditions to confirm state and timestamps are available and accurate.

**Acceptance Scenarios**:

1. **Given** token sync is healthy, **When** an operator checks status, **Then** they can see an explicit "in sync" state and last verification time.
2. **Given** token drift is detected, **When** an operator checks status, **Then** they can see an explicit "out of sync" state with a remediation hint.

______________________________________________________________________

### Edge Cases

- Secret value rotates while users still hold active sessions based on the prior token.
- Temporary unavailability of one token source during sync verification.
- Repeated rapid secret rotations occurring before the previous rotation fully propagates.
- Simultaneous login attempts during a detected token conflict window.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST treat a single defined token source as authoritative for Headlamp authentication decisions at any point in time.
  - **Acceptance Criteria**: For any login attempt, validation is performed against exactly one authoritative source, and that source is identifiable in audit output.
- **FR-002**: The system MUST synchronize authentication behavior to reflect secret updates for all new login attempts within a bounded propagation window.
  - **Acceptance Criteria**: After a secret rotation, new logins use the updated value within 5 minutes.
- **FR-003**: The system MUST detect conflicting token values between active sources and apply a deterministic precedence rule.
  - **Acceptance Criteria**: During a conflict, the selected value and precedence reason are captured for each impacted decision.
- **FR-004**: The system MUST expose token sync health status to operators, including state, last successful verification time, and last failure reason when applicable.
  - **Acceptance Criteria**: Operators can distinguish healthy, degraded, and out-of-sync states without inspecting raw system internals.
- **FR-005**: The system MUST provide actionable user-facing behavior when token mismatch prevents access.
  - **Acceptance Criteria**: Failed logins caused by mismatch present a clear message indicating retry expectations or operator follow-up.
- **FR-006**: The system MUST record auditable events for token synchronization checks, secret rotations observed, conflicts, and authentication outcomes related to token validation.
  - **Acceptance Criteria**: Operators can retrieve a chronological history of sync and auth events for incident triage.
- **FR-007**: The system MUST recover automatically from transient sync-check failures and re-validate token consistency without requiring manual restarts.
  - **Acceptance Criteria**: Following a transient source outage, sync checks resume and state returns to healthy once sources converge.

### Key Entities *(include if feature involves data)*

- **Token Source**: A named origin of token truth (for example, secret store or auth provider view), with attributes for current token fingerprint, last update time, and source priority.
- **Token Sync State**: The current evaluated relationship between token sources (`in_sync`, `degraded`, `out_of_sync`) with timestamps and reason codes.
- **Authentication Decision Record**: A per-login outcome including evaluated source, decision result, and failure category (if denied).
- **Sync Incident**: A grouped operational event describing mismatch detection, duration, affected login attempts, and resolution status.

### Assumptions

- The desired behavior is to prevent stale or conflicting tokens from silently granting or denying access.
- Existing Headlamp login flow remains in place; this feature improves token consistency and observability around that flow.
- Operators need clear operational signals and auditability more than end-user customization for this issue.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 99% of valid Headlamp login attempts succeed on the first attempt during normal operation.
- **SC-002**: 100% of secret rotations are reflected for new login attempts within 5 minutes of the secret update.
- **SC-003**: Token mismatch-related access incidents are detected and surfaced to operators within 1 minute of occurrence.
- **SC-004**: Support interventions related to Headlamp token desynchronization decrease by at least 80% over a 30-day period after rollout.
