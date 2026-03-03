# Phase 0 Research: Authentik Cluster Authentication

## Decision 0: Authentik Deployment Model

- **Decision**: Deploy Authentik as a new in-cluster app managed by Flux under `kubernetes/apps/security/authentik/`.
- **Rationale**: Keeps identity provider lifecycle declarative, reproducible, and version-controlled alongside existing cluster apps.
- **Alternatives considered**:
  - Using an externally managed Authentik instance (rejected: drifts from repo-driven cluster reproducibility)
  - Manual one-time cluster install (rejected: violates GitOps-only operations)

## Decision 1: Migration Strategy

- **Decision**: Use phased route migration with explicit per-route auth-path assignment.
- **Rationale**: Limits blast radius and allows rollback by route while preserving availability for non-migrated apps.
- **Alternatives considered**:
  - Full cutover in one release (rejected: high outage risk)
  - Passive dual-path with no migration target (rejected: unclear completion criteria)

## Decision 2: Unassigned Route Behavior

- **Decision**: Enforce deny-by-default for protected routes lacking explicit auth-path assignment.
- **Rationale**: Prevents accidental bypass and makes misconfiguration immediately visible.
- **Alternatives considered**:
  - Default to Google-proxy (rejected: hides config drift)
  - Default to Authentik (rejected: can produce unexpected access changes)

## Decision 3: Authentication Outcome Retention

- **Decision**: Require queryable authentication outcome records for at least 30 days.
- **Rationale**: Covers operational troubleshooting and change windows without excessive retention burden.
- **Alternatives considered**:
  - 7-day retention (rejected: too short for delayed incident analysis)
  - 90+ day retention (rejected: higher storage/ops overhead for current scope)

## Decision 4: Gateway Integration Pattern

- **Decision**: Route authentication through gateway-managed policy attachments tied to protected routes.
- **Rationale**: Keeps auth enforcement close to ingress control and aligns with existing route-policy patterns.
- **Alternatives considered**:
  - App-side auth enforcement only (rejected: inconsistent coverage)
  - Namespace-wide blanket policy (rejected: insufficient per-route control for phased migration)

## Decision 5: Callback and Host Routing

- **Decision**: Keep explicit host-level routing for auth callback endpoints and avoid wildcard-only behavior.
- **Rationale**: Reduces callback misrouting risk and aligns with existing oauth host-specific ingress rules.
- **Alternatives considered**:
  - Wildcard-only host routing (rejected: callback collisions/404 risk)
  - Per-app callback endpoints (rejected: duplicated policy surface)

## Decision 6: Observability Signals

- **Decision**: Standardize auth outcome signals to include route identifier, auth path, outcome, and timestamp.
- **Rationale**: Supports measurable success criteria and quick operator diagnosis.
- **Alternatives considered**:
  - Success-only logging (rejected: inadequate failure triage)
  - Raw provider logs without route context (rejected: poor traceability)

## Decision 7: Validation Workflow

- **Decision**: Validate via repository standard gates (`task lint` then `task dev:validate`) plus branch testing workflow when live verification is required.
- **Rationale**: Complies with repository constitution and existing CI parity model.
- **Alternatives considered**:
  - Manual cluster apply for ad-hoc tests (rejected: violates GitOps principle)

## Decision 8: Bootstrap Secret Handling

- **Decision**: Require Authentik bootstrap/admin secrets through encrypted or external secret references, and fail deployment when missing.
- **Rationale**: Prevents insecure defaults and makes misconfiguration visible during reconciliation.
- **Alternatives considered**:
  - Hardcoded bootstrap credentials in manifests (rejected: security violation)
  - Auto-generated unmanaged credentials (rejected: poor reproducibility and rotation control)

## Decision 9: Auth-path outage diagnosis runbook

- **Decision**: Add explicit operator diagnosis steps for unavailable `authentik` or `google-proxy` auth paths using route assignment and oauth host routing checks.
- **Rationale**: Operators need deterministic fail-closed triage to recover quickly without exposing routes unsecured.
- **Diagnosis Steps**:
  1. Confirm route assignment in `files/auth-path-matrix.yaml` for impacted host.
  2. Confirm Cloudflare tunnel ingress entry for auth callback and route hostname ordering.
  3. Confirm Envoy SecurityPolicy issuer/client secret references reconcile successfully.
  4. If Authentik is unavailable, roll impacted pilot routes back to `google-proxy` assignment until healthy.
