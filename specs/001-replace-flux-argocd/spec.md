# Feature Specification: Replace Flux with ArgoCD

**Feature Branch**: `[001-replace-flux-argocd]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: User description: "Replace Flux with ArgoCD on this Repo. Implement any bootstrapping necessary"

## Clarifications

### Session 2026-03-13

- Q: Should this feature fully replace Flux now or allow coexistence/deferment? → A: Full replacement in this feature, including migration and decommissioning Flux-managed ownership.
- Q: Should rollback re-activate Flux or remain ArgoCD-only? → A: Rollback remains ArgoCD-only and does not reactivate Flux.
- Q: What ArgoCD access scope should be used? → A: Role-based access with platform admins as write/admin and maintainers as read-only.
- Q: What migration disruption level is acceptable? → A: Brief planned disruption per workload group is acceptable during cutover.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Bootstrap GitOps control on a cluster (Priority: P1)

As a platform operator, I can initialize a cluster so repository state is reconciled by ArgoCD without requiring Flux components.

**Why this priority**: Bootstrapping is the entry point for all GitOps operations; without it, no desired state can be applied safely.

**Independent Test**: Run the bootstrap flow on a cluster with no active GitOps controller, then verify the baseline platform resources reconcile from this repository and remain continuously managed.

**Acceptance Scenarios**:

1. **Given** a cluster with no active GitOps controller, **When** the documented bootstrap process is executed, **Then** ArgoCD becomes active and starts reconciling repository-defined resources.
2. **Given** bootstrap has completed, **When** operators check controller status and managed resources, **Then** they can confirm healthy reconciliation without reliance on Flux.

______________________________________________________________________

### User Story 2 - Fully migrate and replace controller ownership (Priority: P2)

As a platform operator, I can migrate all currently Flux-managed workloads to ArgoCD ownership so desired state behavior remains consistent and Flux ownership is retired.

**Why this priority**: Migration preserves expected service outcomes with controlled, brief cutovers and avoids drift or orphaned resources after replacing Flux.

**Independent Test**: Migrate the representative workload group (`network` namespace routing components plus `default/echo`) and verify migrated workloads stay healthy, synchronized, and recover automatically from manual drift.

**Acceptance Scenarios**:

1. **Given** workloads currently managed via Flux definitions, **When** migration steps are applied, **Then** those workloads become managed through ArgoCD and remain in their expected state.
2. **Given** a migrated workload, **When** an out-of-band change is introduced, **Then** the system restores the declared state within the expected reconciliation window.
3. **Given** cutover is complete, **When** maintainers verify controller ownership, **Then** no in-scope workload remains actively reconciled by Flux.

______________________________________________________________________

### User Story 3 - Operate and recover safely after cutover (Priority: P3)

As a repository maintainer, I can verify migration completion and execute rollback/recovery guidance if a post-cutover issue appears.

**Why this priority**: Operational safety and recovery confidence reduce migration risk and support incident response.

**Independent Test**: Follow the post-migration verification and rollback instructions in a non-production validation run and confirm expected recovery outcomes.

**Acceptance Scenarios**:

1. **Given** migration has been cut over, **When** maintainers run post-migration verification checks, **Then** they receive a clear pass/fail outcome for migration readiness.
2. **Given** a critical post-cutover issue, **When** maintainers execute rollback guidance, **Then** they can restore a known-good managed state without ambiguity and without reactivating Flux.
3. **Given** a repository maintainer without admin privileges, **When** they access ArgoCD, **Then** they can inspect health/sync status but cannot change managed state.

______________________________________________________________________

### Edge Cases

- A cluster has partial Flux artifacts remaining (for example, stale reconciliation objects) that could conflict with ArgoCD ownership.
- Bootstrap is interrupted midway (for example, temporary credentials or cluster access disruption), requiring safe re-run without duplicate ownership.
- Migration order is incorrect for dependent workloads, causing transient health failures that must be detected and surfaced.
- Secrets required by workloads are unavailable or unreadable during cutover, and health checks must clearly identify the blocking condition.
- Planned disruption exceeds the declared cutover window for a workload group and requires rollback or re-sequencing.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The repository MUST provide complete, declarative bootstrap assets to establish ArgoCD as the active GitOps controller for this environment.
- **FR-002**: The migration process MUST define and enforce a single-controller ownership model so Flux and ArgoCD do not simultaneously reconcile the same workload scope after cutover.
- **FR-003**: Operators MUST be able to execute ArgoCD bootstrap end-to-end from documented repository runbooks with no manual, undocumented steps.
- **FR-004**: The system MUST preserve declared workload outcomes currently managed by GitOps before and after migration.
- **FR-005**: The migration flow MUST include dependency-aware sequencing, including explicit ArgoCD sync-wave ordering and health checks where ordering matters, so prerequisite platform components reconcile before dependent applications.
- **FR-006**: The process MUST provide explicit verification steps that confirm controller health, application synchronization status, and reconciliation behavior after cutover.
- **FR-007**: The process MUST provide an operator-usable rollback path to a previously known-good managed state if migration verification fails, without reactivating Flux.
- **FR-008**: The repository MUST include updated operational documentation describing bootstrap, migration, verification, and rollback responsibilities.
- **FR-009**: The migration MUST preserve secure handling of encrypted configuration and secrets needed for workload reconciliation.
- **FR-010**: The process MUST surface actionable failure states for bootstrap and migration steps so operators can diagnose and recover.
- **FR-011**: The feature MUST include completion criteria and operator steps to retire Flux reconciliation ownership for all in-scope workloads.
- **FR-012**: The feature MUST define role-based access so platform admins can manage ArgoCD state changes and non-admin maintainers have read-only visibility.
- **FR-013**: The migration MUST define per-workload cutover windows and operator communication steps for brief planned disruption during ownership transition.
- **FR-014**: The process MUST record per-wave first-pass verification outcomes and elapsed cutover/rollback durations to validate success criteria.

### Key Entities *(include if feature involves data)*

- **GitOps Controller State**: Represents which controller is active, its health status, and its ownership scope.
- **Managed Workload Group**: Represents a set of related workloads with dependency order and expected health/sync outcomes.
- **Bootstrap Run**: Represents one execution of initialization, including prerequisites, completion status, and failure checkpoints.
- **Migration Verification Result**: Represents pass/fail outcomes for post-cutover checks and supporting evidence.
- **Rollback Procedure**: Represents defined recovery actions, triggers, and expected restored state.

### Assumptions & Dependencies

- All workloads currently reconciled by Flux are in scope for migration and ownership cutover in this feature.
- Cluster access, required credentials, and encrypted secret material are available to authorized operators during bootstrap and migration.
- Migration is executed in controlled waves to reduce blast radius and allow verification between phases.
- A non-production validation cycle is available before final production cutover.
- Platform admins and non-admin maintainers are identifiable groups that can be assigned distinct access privileges.
- The representative workload group used for independent migration validation is `network` plus `default/echo`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can bootstrap GitOps control on a target cluster and reach healthy baseline reconciliation within 30 minutes.
- **SC-002**: 100% of workloads previously managed by Flux are managed after cutover with no unresolved critical drift findings.
- **SC-003**: At least 95% of migrated workload groups pass post-cutover verification on first attempt during planned migration runs.
- **SC-004**: In rollback drills, operators restore a known-good managed state within 15 minutes using documented procedures only.
- **SC-005**: For each migrated workload group, user-visible planned disruption during cutover stays within 10 minutes.
