# Research: Headlamp Token Sync Reliability

## 1. Authoritative Token Source

**Decision**: Treat the Kubernetes Secret materialized by External Secrets (`headlamp-admin-token`
in `observability`) as the runtime source of truth for Headlamp token validation.

**Rationale**: 1Password is the upstream system, but authentication in-cluster executes against the
materialized Kubernetes Secret. Declaring that secret as authoritative for runtime checks removes
ambiguity during incidents and aligns with the actual data path used by workloads.

**Alternatives considered**:

- **Directly trust 1Password value at request time**: Rejected because runtime auth does not query
  1Password per request and would introduce extra dependency latency/failure modes.
- **Treat Envoy session cookies as equivalent token truth**: Rejected because cookies represent
  OIDC session state, not the Headlamp admin token lifecycle.

______________________________________________________________________

## 2. Conflict and Precedence Handling

**Decision**: Use deterministic precedence: `ExternalSecret Ready + target Secret value` is the
active value for new logins. Any mismatch with observed auth behavior is recorded as a sync incident.

**Rationale**: This supports FR-001 and FR-003 by guaranteeing one decision path for each login and
providing explainable outcomes when sources diverge.

**Precedence metadata**:

- `authoritativeSource`: `k8s-secret`
- `sourcePriority`: `k8s-secret=10`, `onepassword=20`, `envoy-session=30`
- `reasonCode` set from deterministic outcomes:
  - `sources_match`
  - `source_unavailable`
  - `fingerprint_mismatch`

**Conflict handling**:

- Mismatch opens/updates a `SyncIncident` in `open` state.
- During automated checks or operator action, status transitions to `mitigating`.
- On convergence, state is set to `resolved` and close timestamp is recorded.

**Alternatives considered**:

- **Last writer wins across components**: Rejected because it is non-deterministic and hard to audit.
- **Manual operator override only**: Rejected due to slower recovery and avoidable toil.

______________________________________________________________________

## 3. Propagation Window for Secret Rotation

**Decision**: Set the feature target that new logins reflect rotated values within 5 minutes, and
treat misses outside this window as actionable incidents.

**Rationale**: This aligns with the spec success criteria and gives operators a measurable SLO for
token consistency.

**Alternatives considered**:

- **Instant propagation requirement**: Rejected as unrealistic in GitOps + reconciliation workflows.
- **No bounded window**: Rejected because it is not testable or operationally enforceable.

______________________________________________________________________

## 4. Drift Detection and Operator Visibility

**Decision**: Surface explicit sync state (`in_sync`, `degraded`, `out_of_sync`) with timestamps,
reason codes, and affected decision history.

**Rationale**: Existing runbooks focus on OIDC failure triage; this feature needs a direct signal
for token drift to prevent prolonged hidden failures.

**Alternatives considered**:

- **Only rely on ad-hoc logs**: Rejected because it slows diagnosis and is not user-friendly.
- **Only detect during failed user login**: Rejected since proactive detection is required.

______________________________________________________________________

## 5. Validation Workflow

**Decision**: Keep repository-standard validation as the default gate:
`task lint` followed by `task dev:validate`, then optional targeted runtime checks.

**Rationale**: This is consistent with repository rules and catches structural or rendering errors
before cluster-side verification.

**Alternatives considered**:

- **Cluster-only validation**: Rejected because it bypasses fast local quality gates.
- **Custom one-off scripts**: Rejected to avoid divergence from established workflows.

______________________________________________________________________

## 6. Integration Pattern with Envoy OAuth

**Decision**: Preserve existing Envoy OAuth policy design and add explicit observability around
token-source evaluation rather than changing gateway ownership of authentication.

**Rationale**: Envoy OAuth is a shared cross-app control plane; minimizing behavioral change lowers
risk while still resolving token sync ambiguity.

**Alternatives considered**:

- **Move all auth decisions into Envoy-only flow**: Rejected due to broader impact and migration risk.
- **Bypass Envoy for Headlamp**: Rejected because it conflicts with existing protected-route design.
