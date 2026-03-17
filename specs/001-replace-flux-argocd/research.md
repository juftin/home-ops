# Research: Replace Flux with ArgoCD

## Decision 1: Bootstrap ArgoCD via existing Helmfile bootstrap flow

**Decision**: Extend the current Helmfile bootstrap sequence to install ArgoCD and establish
ArgoCD-managed reconciliation from Git.

**Rationale**: The repository already relies on Helmfile for ordered cluster bootstrap and
reproducibility. Reusing this pattern preserves known operator workflows and keeps controller
installation declarative.

**Alternatives considered**:

- Install ArgoCD manually with ad-hoc commands (rejected: violates reproducibility).
- Bootstrap ArgoCD entirely outside `bootstrap/` (rejected: fragments bootstrap ownership).

______________________________________________________________________

## Decision 2: Use wave-based ownership cutover with single-controller enforcement

**Decision**: Migrate workload ownership in dependency-aware waves and retire Flux ownership for
each wave before proceeding.

**Rationale**: This directly satisfies the clarified requirement for full replacement in this
feature while minimizing blast radius and preventing dual-controller drift.

**Alternatives considered**:

- Big-bang cutover of all workloads (rejected: higher outage and rollback risk).
- Long-term Flux/ArgoCD coexistence (rejected: conflicts with clarified scope and FR-002).

______________________________________________________________________

## Decision 3: Preserve SOPS+age model and provide ArgoCD decryption parity

**Decision**: Keep encrypted secrets unchanged and configure ArgoCD reconciliation to support SOPS
decryption with existing age key material.

**Rationale**: This preserves current security posture, avoids secret format churn, and enables
cutover without rewriting secret assets.

**Alternatives considered**:

- Migrate all secrets to a new encryption system first (rejected: unnecessary scope expansion).
- Temporary plaintext conversion during migration (rejected: violates constitution/security rules).

______________________________________________________________________

## Decision 4: Enforce role-based ArgoCD access policy

**Decision**: Define role-based access with platform admins granted write/admin capabilities and
maintainers granted read-only visibility.

**Rationale**: Matches approved clarification and keeps operational control aligned with least
privilege while preserving visibility for non-admin maintainers.

**Alternatives considered**:

- Admin-only access for all users (rejected: blocks maintainer visibility goals).
- Full admin for maintainers (rejected: exceeds least-privilege requirements).

______________________________________________________________________

## Decision 5: Validate with both offline rendering and post-cutover health checks

**Decision**: Keep offline validation gates for manifest rendering and add explicit post-cutover
ArgoCD health/sync/drift verification checkpoints.

**Rationale**: Offline checks preserve fast feedback in PR workflows, while post-cutover checks
prove runtime correctness and ownership transfer success.

**Alternatives considered**:

- Runtime-only validation (rejected: slower feedback and higher rework).
- Offline-only validation (rejected: cannot prove live controller health/sync behavior).

______________________________________________________________________

## Resolved Technical Context Unknowns

- No unresolved `NEEDS CLARIFICATION` items remain for Phase 1 design.
- Performance and disruption targets are taken from spec success criteria (`SC-001`, `SC-004`,
  `SC-005`).
- Security, access, and rollback model are fully resolved by clarification session decisions.
