# Data Model: Headlamp Token Sync Reliability

## Entities

### 1. TokenSource

Represents a concrete source participating in token evaluation.

| Field          | Type      | Description                                                      | Validation                                                                     |
| -------------- | --------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `name`         | string    | Source identifier (`k8s-secret`, `onepassword`, `envoy-session`) | Required; unique in scope                                                      |
| `kind`         | enum      | Source category                                                  | Must be one of `materialized_secret`, `upstream_secret_store`, `session_token` |
| `fingerprint`  | string    | Non-sensitive digest of current token value                      | Required; never store raw token                                                |
| `observedAt`   | timestamp | Last observation time                                            | Required                                                                       |
| `priority`     | integer   | Precedence order for decisioning                                 | Required; lower number = higher priority                                       |
| `availability` | enum      | Current source health                                            | `available`, `degraded`, `unavailable`                                         |

### 2. TokenSyncState

Represents current cross-source consistency state.

| Field                 | Type           | Description                                 | Validation                               |
| --------------------- | -------------- | ------------------------------------------- | ---------------------------------------- |
| `state`               | enum           | Current sync health                         | `in_sync`, `degraded`, `out_of_sync`     |
| `authoritativeSource` | string         | Name of source currently used for decisions | Required; must map to `TokenSource.name` |
| `lastVerifiedAt`      | timestamp      | Last successful sync check                  | Required                                 |
| `lastFailureAt`       | timestamp/null | Most recent failed verification             | Optional                                 |
| `reasonCode`          | string/null    | Short machine-readable reason               | Required when state != `in_sync`         |
| `details`             | string/null    | Operator-facing context                     | Optional                                 |

### 3. AuthDecisionRecord

Represents a single login decision tied to token evaluation.

| Field             | Type      | Description                         | Validation                                                    |
| ----------------- | --------- | ----------------------------------- | ------------------------------------------------------------- |
| `decisionId`      | string    | Unique request/login decision ID    | Required; unique                                              |
| `evaluatedAt`     | timestamp | Decision time                       | Required                                                      |
| `sourceUsed`      | string    | Token source used for this decision | Required; must match authoritative source                     |
| `result`          | enum      | Outcome                             | `allow`, `deny`                                               |
| `failureCategory` | enum/null | Why denied                          | `token_mismatch`, `source_unavailable`, `policy_denied`, null |
| `userMessage`     | string    | User-facing error/success hint      | Required                                                      |

### 4. SyncIncident

Represents a grouped drift/degradation event for operators.

| Field               | Type           | Description                        | Validation                                         |
| ------------------- | -------------- | ---------------------------------- | -------------------------------------------------- |
| `incidentId`        | string         | Unique incident identifier         | Required; unique                                   |
| `openedAt`          | timestamp      | Incident start time                | Required                                           |
| `closedAt`          | timestamp/null | Incident end time                  | Null until resolved                                |
| `status`            | enum           | Incident lifecycle                 | `open`, `mitigating`, `resolved`                   |
| `trigger`           | enum           | How incident was detected          | `scheduled_check`, `login_failure`, `manual_check` |
| `affectedDecisions` | integer        | Number of impacted auth decisions  | Required; >= 0                                     |
| `remediationHint`   | string         | Suggested next action for operator | Required                                           |

## Relationships

- `TokenSyncState.authoritativeSource` references one active `TokenSource`.
- `AuthDecisionRecord.sourceUsed` references the authoritative `TokenSource` at decision time.
- `SyncIncident` aggregates one or more `AuthDecisionRecord` entries during drift windows.

## State Transitions

### TokenSyncState

`in_sync` → `degraded` when a required source becomes unavailable but no mismatch is confirmed.

`in_sync` or `degraded` → `out_of_sync` when fingerprints diverge for active sources.

`degraded` or `out_of_sync` → `in_sync` after successful re-verification and source convergence.

### SyncIncident

`open` → `mitigating` once automated retries or operator action starts.

`mitigating` → `resolved` when sync state returns to `in_sync` and verification passes.

## Derived Validation Rules from Requirements

- Exactly one authoritative source must exist for any decision window (FR-001).
- Secret rotation must be reflected for new decisions within 5 minutes (FR-002).
- Conflicts must capture precedence reason and chosen source (FR-003).
- Non-healthy states must expose timestamps and reason codes (FR-004).
- Denied decisions due to mismatch must include actionable user messaging (FR-005).

## Shared Status Persistence Contract

Token sync state is persisted in ConfigMap-backed payloads so operators can read current status without
direct pod log inspection.

- ConfigMap: `headlamp-token-sync-state` (namespace: `observability`)
- Required keys:
  - `status.json` (single `TokenSyncStatus`)
  - `sources.json` (`TokenSource[]` under `items`)
  - `incidents.json` (`SyncIncident[]` under `items`)
  - `incident-template-open.json`, `incident-template-mitigating.json`,
    `incident-template-resolved.json`
- Retention policy:
  - Keep active status payloads in-cluster
  - Retain incident payload history for 14 days before archival/rotation
