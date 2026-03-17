# Data Model: Replace Flux with ArgoCD

This model translates the feature specification into planning entities used to design migration
tasks, contracts, and verification checkpoints.

______________________________________________________________________

## Entity: GitOpsControllerState

Represents controller ownership and operational state for a cluster scope.

| Field            | Type                                                            | Description                                        | Validation                                      |
| ---------------- | --------------------------------------------------------------- | -------------------------------------------------- | ----------------------------------------------- |
| `controllerName` | enum(`flux`,`argocd`)                                           | Active reconciler identity                         | Must be one of allowed values                   |
| `ownershipScope` | string                                                          | Scope currently reconciled (e.g., namespace group) | Non-empty                                       |
| `status`         | enum(`inactive`,`bootstrapping`,`reconciling`,`decommissioned`) | Lifecycle status                                   | Valid transition only                           |
| `lastHealthyAt`  | datetime                                                        | Last confirmed healthy reconcile state             | Optional until first healthy reconcile          |
| `evidenceRef`    | string                                                          | Link/path to verification output                   | Required for `reconciling` and `decommissioned` |

**State transitions**:

`inactive -> bootstrapping -> reconciling -> decommissioned`

`reconciling -> inactive` is invalid for this feature after full cutover decision.

______________________________________________________________________

## Entity: ManagedWorkloadGroup

Represents a dependency-ordered group of workloads transferred in one migration wave.

| Field                  | Type                                                   | Description                                     | Validation                     |
| ---------------------- | ------------------------------------------------------ | ----------------------------------------------- | ------------------------------ |
| `groupId`              | string                                                 | Stable workload group identifier                | Unique                         |
| `namespaces`           | list<string>                                           | Namespaces included in the wave                 | At least one namespace         |
| `dependencies`         | list<string>                                           | Other `groupId` values that must complete first | Must reference existing groups |
| `cutoverWindowMinutes` | integer                                                | Planned disruption window for this wave         | `1 <= value <= 10`             |
| `targetController`     | enum(`argocd`)                                         | Intended reconciler after wave completion       | Must be `argocd`               |
| `cutoverStatus`        | enum(`pending`,`in_progress`,`verified`,`rolled_back`) | Wave execution state                            | Valid transition only          |

**State transitions**:

`pending -> in_progress -> verified`

`in_progress -> rolled_back`

`rolled_back -> pending` (if reattempt approved)

______________________________________________________________________

## Entity: BootstrapRun

Represents one execution of controller bootstrap for a target cluster.

| Field           | Type                               | Description                             | Validation                          |
| --------------- | ---------------------------------- | --------------------------------------- | ----------------------------------- |
| `runId`         | string                             | Unique bootstrap identifier             | Unique                              |
| `initiatedBy`   | string                             | Operator identity                       | Non-empty                           |
| `startedAt`     | datetime                           | Bootstrap start time                    | Required                            |
| `completedAt`   | datetime                           | Bootstrap completion time               | Required for terminal states        |
| `result`        | enum(`success`,`failed`,`aborted`) | Final outcome                           | Required when terminal              |
| `failureReason` | string                             | Error summary if failed                 | Required when `result=failed`       |
| `artifacts`     | list<string>                       | Paths/refs for logs and health evidence | At least one artifact on completion |

**Business rule**: successful runs must meet SC-001 bootstrap readiness target (\<=30 minutes).

______________________________________________________________________

## Entity: MigrationVerificationResult

Represents post-wave or post-cutover validation outcomes.

| Field             | Type                        | Description                  | Validation |
| ----------------- | --------------------------- | ---------------------------- | ---------- |
| `verificationId`  | string                      | Unique verification record   | Unique     |
| `scope`           | enum(`wave`,`full-cutover`) | Validation scope             | Required   |
| `scopeRef`        | string                      | Wave ID or cutover ID        | Required   |
| `healthCheckPass` | boolean                     | ArgoCD health checks passed  | Required   |
| `syncCheckPass`   | boolean                     | Desired state synchronized   | Required   |
| `driftCheckPass`  | boolean                     | No unresolved critical drift | Required   |
| `verifiedAt`      | datetime                    | Verification timestamp       | Required   |
| `notes`           | string                      | Operator notes and anomalies | Optional   |

**Business rule**: full cutover verification must have all checks true before Flux retirement is
considered complete.

______________________________________________________________________

## Entity: RollbackProcedure

Represents an ArgoCD-only rollback plan and execution trail.

| Field               | Type                                              | Description                          | Validation             |
| ------------------- | ------------------------------------------------- | ------------------------------------ | ---------------------- |
| `rollbackId`        | string                                            | Unique rollback execution ID         | Unique                 |
| `triggerCondition`  | string                                            | Condition that triggered rollback    | Non-empty              |
| `targetScope`       | string                                            | Wave/cutover scope being rolled back | Non-empty              |
| `steps`             | list<string>                                      | Ordered operator actions             | At least one step      |
| `restorationStatus` | enum(`pending`,`in_progress`,`restored`,`failed`) | Rollback status                      | Valid transition only  |
| `restoredAt`        | datetime                                          | Restoration completion timestamp     | Required when restored |

**Business rule**: successful rollback should restore known-good state within 15 minutes (SC-004).

______________________________________________________________________

## Entity: AccessPolicyBinding

Represents role-based ArgoCD access assignments.

| Field         | Type                                   | Description                      | Validation |
| ------------- | -------------------------------------- | -------------------------------- | ---------- |
| `bindingId`   | string                                 | Unique policy binding identifier | Unique     |
| `subjectType` | enum(`user`,`group`,`service-account`) | Identity type                    | Required   |
| `subjectName` | string                                 | Identity principal name          | Non-empty  |
| `role`        | enum(`admin`,`read-only`)              | ArgoCD role                      | Required   |
| `scope`       | string                                 | Application/project scope        | Non-empty  |
| `status`      | enum(`active`,`revoked`)               | Binding lifecycle                | Required   |

**Business rule**: maintainers must only be assigned `read-only`; admin grants are restricted to
platform admin subjects.
