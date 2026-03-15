# Tasks: Replace Flux with ArgoCD

**Input**: Design documents from `/specs/001-replace-flux-argocd/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/, quickstart.md

**Tests**: No new automated test suite requested in spec; validation tasks use existing repo gates and rollout verification steps.

**Organization**: Tasks are grouped by user story so each story can be implemented and validated independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: User story mapping label (`[US1]`, `[US2]`, `[US3]`)
- Every task includes at least one concrete file path

______________________________________________________________________

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize ArgoCD rollout scaffolding in repository structure.

- [ ] T001 Create ArgoCD manifest directory scaffold in `kubernetes/argocd/kustomization.yaml`
- [ ] T002 Create ArgoCD resource skeletons in `kubernetes/argocd/appproject.yaml`, `kubernetes/argocd/applicationset.yaml`, and `kubernetes/argocd/rbac.yaml`
- [ ] T003 [P] Add ArgoCD bootstrap release scaffold in `bootstrap/helmfile.d/01-apps.yaml`
- [ ] T004 [P] Add ArgoCD values scaffold in `bootstrap/helmfile.d/templates/values.yaml.gotmpl`
- [ ] T005 [P] Create rollout script entrypoints with strict mode in `scripts/migrate-argocd-wave.sh`, `scripts/verify-argocd-cutover.sh`, and `scripts/rollback-argocd-wave.sh`

______________________________________________________________________

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build shared rollout plumbing required before any user story implementation.

**⚠️ CRITICAL**: No user story work starts until this phase completes.

- [ ] T006 Implement shared rollout helper functions in `scripts/lib/common.sh`
- [ ] T007 Define shared wave ordering and disruption-budget constants in `scripts/migrate-argocd-wave.sh` and `scripts/verify-argocd-cutover.sh`
- [ ] T008 [P] Add ArgoCD-focused dev tasks in `.taskfiles/dev/Taskfile.yaml`
- [ ] T009 Update bootstrap orchestration messaging/check hooks in `scripts/bootstrap-apps.sh`
- [ ] T010 [P] Add rollout runbook placeholders and command index links in `docs/ARGOCD-ROLLOUT.md` and `docs/TASKS.md`

**Checkpoint**: Foundation ready — user stories can proceed in priority order.

______________________________________________________________________

## Phase 3: User Story 1 - Bootstrap GitOps control on a cluster (Priority: P1) 🎯 MVP

**Goal**: Bootstrap ArgoCD as active GitOps controller from repository-defined resources.

**Independent Test**: Execute bootstrap flow on a cluster with no active GitOps controller and confirm ArgoCD reaches healthy reconciliation without Flux reliance.

### Implementation for User Story 1

- [ ] T011 [US1] Implement ArgoCD Helm release dependency ordering in `bootstrap/helmfile.d/01-apps.yaml`
- [ ] T012 [US1] Implement ArgoCD bootstrap values (controller config and decryption parity) in `bootstrap/helmfile.d/templates/values.yaml.gotmpl`
- [ ] T013 [P] [US1] Define ArgoCD AppProject scope, required application health policies, and guardrails in `kubernetes/argocd/appproject.yaml`
- [ ] T014 [P] [US1] Define ArgoCD ApplicationSet generation with explicit sync-wave annotations for ordered reconciliation of `kubernetes/apps/*` in `kubernetes/argocd/applicationset.yaml`
- [ ] T015 [US1] Wire ArgoCD resources into root kustomization in `kubernetes/argocd/kustomization.yaml`
- [ ] T016 [US1] Document bootstrap execution and readiness checks in `docs/ARGOCD-BOOTSTRAP.md`
- [ ] T017 [US1] Add bootstrap command wrappers and usage notes in `Taskfile.yaml` and `docs/TASKS.md`

**Checkpoint**: User Story 1 can bootstrap and validate ArgoCD reconciliation independently.

______________________________________________________________________

## Phase 4: User Story 2 - Fully migrate and replace controller ownership (Priority: P2)

**Goal**: Transfer workload ownership from Flux to ArgoCD in dependency-aware waves with verification.

**Independent Test**: Migrate a representative wave, verify health/sync/drift outcomes, and confirm no migrated workload remains Flux-reconciled.

### Implementation for User Story 2

- [ ] T018 [US2] Implement wave cutover orchestration flow in `scripts/migrate-argocd-wave.sh`
- [ ] T019 [P] [US2] Implement wave verification checks (health/sync/drift/ownership), secret-unavailable failure-path validation, and contract-conformance assertions from `specs/001-replace-flux-argocd/contracts/rollout-api.openapi.yaml` in `scripts/verify-argocd-cutover.sh`
- [ ] T020 [P] [US2] Add migration, ArgoCD render validation, and post-cutover health verification task wrappers in `.taskfiles/dev/Taskfile.yaml`
- [ ] T021 [US2] Implement phased Flux ownership retirement logic in `kubernetes/flux/cluster/ks.yaml`
- [ ] T022 [US2] Document migration wave sequencing and communication steps in `docs/ARGOCD-MIGRATION.md`
- [ ] T023 [US2] Update rollout quickstart migration section with representative workload group definition and first-pass success-rate evidence capture (SC-003) in `specs/001-replace-flux-argocd/quickstart.md`

**Checkpoint**: User Story 2 migrates waves with verified ownership cutover and disruption limits.

______________________________________________________________________

## Phase 5: User Story 3 - Operate and recover safely after cutover (Priority: P3)

**Goal**: Provide ArgoCD-only rollback and role-based operational access for maintainers/admins.

**Independent Test**: Execute rollback drill from runbook and validate admin/read-only policy behavior in ArgoCD access checks.

### Implementation for User Story 3

- [ ] T024 [US3] Implement ArgoCD-only rollback workflow with safety guards in `scripts/rollback-argocd-wave.sh`
- [ ] T025 [P] [US3] Implement admin/read-only ArgoCD policy bindings in `kubernetes/argocd/rbac.yaml`
- [ ] T026 [P] [US3] Add rollback and RBAC validation tasks in `.taskfiles/dev/Taskfile.yaml`
- [ ] T027 [US3] Document rollback drill, elapsed-time capture for SC-004, and access validation procedure in `docs/ARGOCD-ROLLOUT.md`
- [ ] T028 [US3] Extend post-cutover operational checks in `docs/POST-MERGE-VERIFICATION.md`

**Checkpoint**: User Story 3 supports safe rollback and least-privilege operations independently.

______________________________________________________________________

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final consistency, documentation alignment, and validation evidence.

- [ ] T029 [P] Update canonical docs from Flux-first to ArgoCD-first narrative in `README.md` and `docs/ARCHITECTURE.md`
- [ ] T030 [P] Normalize script usage/help output and executable mode in `scripts/migrate-argocd-wave.sh`, `scripts/verify-argocd-cutover.sh`, and `scripts/rollback-argocd-wave.sh`
- [ ] T031 Capture rollout verification command evidence in `specs/001-replace-flux-argocd/quickstart.md`
- [ ] T032 Run repo validation gates and record outcomes in `specs/001-replace-flux-argocd/quickstart.md` using `task lint`, `task dev:validate`, and ArgoCD render/health checks exposed in `.taskfiles/dev/Taskfile.yaml`

______________________________________________________________________

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: starts immediately
- **Phase 2 (Foundational)**: depends on Phase 1; blocks all user stories
- **Phase 3 (US1)**: depends on Phase 2; defines MVP
- **Phase 4 (US2)**: depends on US1 bootstrap readiness
- **Phase 5 (US3)**: depends on US2 migration flow and verification outputs
- **Phase 6 (Polish)**: depends on all user stories being complete

### User Story Dependencies

- **US1 (P1)**: independent after foundational completion
- **US2 (P2)**: depends on US1 ArgoCD bootstrap availability
- **US3 (P3)**: depends on US2 cutover workflow and verification artifacts

______________________________________________________________________

## Parallel Opportunities

- **Setup**: `T003`, `T004`, and `T005` can run in parallel after `T001`/`T002`
- **Foundational**: `T008` and `T010` can run in parallel after `T006`/`T007`
- **US1**: `T013` and `T014` can run in parallel after `T011`/`T012`
- **US2**: `T019` and `T020` can run in parallel after `T018`
- **US3**: `T025` and `T026` can run in parallel after `T024`
- **Polish**: `T029` and `T030` can run in parallel before final validation tasks

______________________________________________________________________

## Parallel Example: User Story 1

```bash
# Parallel ArgoCD resource authoring after bootstrap values/release are in place
Task: "T013 [US1] Define ArgoCD AppProject scope in kubernetes/argocd/appproject.yaml"
Task: "T014 [US1] Define ApplicationSet generation in kubernetes/argocd/applicationset.yaml"
```

## Parallel Example: User Story 2

```bash
# Parallel migration support once cutover orchestration exists
Task: "T019 [US2] Implement verification checks in scripts/verify-argocd-cutover.sh"
Task: "T020 [US2] Add migration wrappers in .taskfiles/dev/Taskfile.yaml"
```

## Parallel Example: User Story 3

```bash
# Parallel operational hardening after rollback core flow is implemented
Task: "T025 [US3] Implement role bindings in kubernetes/argocd/rbac.yaml"
Task: "T026 [US3] Add rollback/RBAC validation tasks in .taskfiles/dev/Taskfile.yaml"
```

______________________________________________________________________

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 and Phase 2.
2. Complete Phase 3 (US1).
3. Validate ArgoCD bootstrap independently.
4. Stop for MVP review before migration cutover tasks.

### Incremental Delivery

1. Deliver US1 bootstrap capability.
2. Add US2 migration waves and ownership retirement.
3. Add US3 rollback and role-based operational controls.
4. Finish polish tasks and re-run validation gates.

### Team Parallelism

1. One engineer completes Setup + Foundational phases.
2. After foundation:
   - Engineer A drives US1 controller/bootstrap resources.
   - Engineer B prepares US2 migration/verification scripts.
   - Engineer C prepares US3 rollback/RBAC artifacts.
3. Merge by dependency order (US1 -> US2 -> US3).

______________________________________________________________________

## Notes

- `[P]` tasks target different files and are safe for parallel execution.
- Story labels map each task to independently testable outcomes.
- Keep each commit scoped to one task or a tightly coupled task pair.
- Re-run existing repo validation gates before marking a phase complete.
