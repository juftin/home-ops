# Phase 0 Research: Envoy Authentik Authentication Migration

## Decision 1: Authentication mode scope

- **Decision**: Use a single cluster-wide authentication mode switch that applies to all protected routes.
- **Rationale**: Prevents split-brain access behavior and keeps rollout/rollback deterministic.
- **Alternatives considered**:
  - Per-namespace mode: rejected due to mixed policy complexity.
  - Per-route mode: rejected due to high operational overhead and inconsistent incident response.

## Decision 2: Unavailable external authorization behavior

- **Decision**: Fail closed when Authentik decision cannot be obtained.
- **Rationale**: Aligns with least-privilege and avoids accidental unauthorized access during dependency outages.
- **Alternatives considered**:
  - Fail open: rejected as security risk.
  - Cached allow fallback: rejected due to stale authorization risk and unclear revocation semantics.

## Decision 3: Minimum observable auth outcome fields

- **Decision**: Require timestamp, identity subject, protected route, decision outcome, and denial reason (for denied requests).
- **Rationale**: Provides sufficient forensic context for incident handling while remaining implementation-agnostic.
- **Alternatives considered**:
  - Decision-only logs: rejected as insufficient for investigation.
  - Subject + decision only: rejected due to missing route-level traceability.

## Decision 4: Validation and release gates

- **Decision**: Use repository-standard gates: `task lint` then `task dev:validate`, plus branch testing (`task dev:start`/`task dev:stop`) for live checks.
- **Rationale**: Matches existing CI/render workflow and prevents invalid manifests from reaching reconciliation.
- **Alternatives considered**:
  - Ad-hoc kubectl testing: rejected by repository GitOps rules.
  - Skipping live branch validation: rejected for security-path changes.

## Decision 5: Availability target handling

- **Decision**: Best-effort reliability for this phase; no formal SLO commitment added.
- **Rationale**: Explicitly clarified in spec scope and avoids introducing unsupported reliability commitments.
- **Alternatives considered**:
  - 99.5% or 99.9% SLO targets: deferred until platform-level reliability policy is defined.

## Decision 6: Future Terraform transition compatibility

- **Decision**: Keep configuration model declarative and mode-driven so ownership can move to Terraform without behavior changes.
- **Rationale**: Reduces migration risk and avoids coupling runtime semantics to current tooling only.
- **Alternatives considered**:
  - Terraform-first redesign now: rejected as out of scope for this feature.
