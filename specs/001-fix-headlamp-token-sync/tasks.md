______________________________________________________________________

## description: "Task list for Headlamp token sync reliability"

# Tasks: Headlamp Token Sync Reliability

**Input**: Design documents from `/specs/001-fix-headlamp-token-sync/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/, quickstart.md

**Tests**: No explicit TDD requirement in spec; implementation and validation tasks only.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Observability app manifests: `kubernetes/apps/observability/...`
- OAuth policy manifests: `kubernetes/apps/network/envoy-gateway/app/...`
- Feature docs: `specs/001-fix-headlamp-token-sync/...`

______________________________________________________________________

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare feature-specific manifest scaffolding and ensure all design artifacts are wired for implementation.

- [x] T001 Create token sync manifest scaffolding under `kubernetes/apps/observability/headlamp/app/` (`token-sync-configmap.yaml`, `token-sync-rbac.yaml`, `token-sync-cronjob.yaml`)
- [x] T002 [P] Create status app scaffolding under `kubernetes/apps/observability/token-sync-status/` (`ks.yaml`, `app/kustomization.yaml`, `app/ocirepository.yaml`, `app/helmrelease.yaml`, `app/httproute.yaml`)
- [x] T003 [P] Register new status app in `kubernetes/apps/observability/kustomization.yaml`

______________________________________________________________________

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Define shared precedence, state storage, and RBAC prerequisites required by all user stories.

**⚠️ CRITICAL**: User story implementation should not begin until these tasks are complete.

- [x] T004 Define global token precedence and reason-code configuration in `kubernetes/apps/observability/headlamp/app/token-sync-configmap.yaml`
- [x] T005 [P] Define ServiceAccount/Role/RoleBinding for sync checks in `kubernetes/apps/observability/headlamp/app/token-sync-rbac.yaml`
- [x] T006 [P] Register foundational token sync resources in `kubernetes/apps/observability/headlamp/app/kustomization.yaml`
- [x] T007 [P] Add shared status persistence contract (ConfigMap layout and retention policy) to `specs/001-fix-headlamp-token-sync/data-model.md`
- [x] T008 Capture foundational operational checks in `specs/001-fix-headlamp-token-sync/quickstart.md`

**Checkpoint**: Token precedence is declarative, RBAC is in place, and shared state shape is documented.

______________________________________________________________________

## Phase 3: User Story 1 - Keep login access aligned with current secret (Priority: P1) 🎯 MVP

**Goal**: Ensure new Headlamp logins consistently follow the current materialized secret after rotations.

**Independent Test**: Rotate the `headlamp-admin-token` value in 1Password, wait for reconciliation, and verify new login behavior aligns with the rotated value within 5 minutes.

- [x] T009 [US1] Set explicit synchronization window (`refreshInterval`) and target policy in `kubernetes/apps/observability/headlamp/app/externalsecret.yaml`
- [x] T010 [P] [US1] Ensure secret-change driven rollout behavior in `kubernetes/apps/observability/headlamp/app/helmrelease.yaml` (reloader annotations bound to `headlamp-admin-token`)
- [x] T011 [US1] Add US1 rotation verification steps and pass/fail criteria to `specs/001-fix-headlamp-token-sync/quickstart.md`
- [x] T012 [US1] Document authoritative-source rule and expected operator action in `docs/OIDC-TROUBLESHOOTING.md`

**Checkpoint**: Secret rotations are bounded and repeatable, with clear runbook guidance for operators.

______________________________________________________________________

## Phase 4: User Story 2 - Resolve token-source conflicts predictably (Priority: P2)

**Goal**: Detect token-source conflicts and enforce deterministic precedence with auditable incident context.

**Independent Test**: Introduce a token-source mismatch and verify the precedence rule is applied, incident state is recorded, and new decisions follow the selected authoritative source.

- [x] T013 [US2] Implement sync-check execution manifest in `kubernetes/apps/observability/headlamp/app/token-sync-cronjob.yaml` to compare authoritative source fingerprints and emit reason codes
- [x] T014 [P] [US2] Add conflict incident state object template in `kubernetes/apps/observability/headlamp/app/token-sync-configmap.yaml` (`open`, `mitigating`, `resolved`)
- [x] T015 [P] [US2] Add precedence metadata and conflict handling notes to `specs/001-fix-headlamp-token-sync/research.md`
- [x] T016 [US2] Wire cronjob and RBAC resources in `kubernetes/apps/observability/headlamp/app/kustomization.yaml`
- [x] T017 [US2] Add conflict simulation and expected-resolution steps to `specs/001-fix-headlamp-token-sync/quickstart.md`

**Checkpoint**: Conflicts are handled deterministically and captured with actionable context.

______________________________________________________________________

## Phase 5: User Story 3 - Provide operational visibility for token sync health (Priority: P3)

**Goal**: Expose sync health, source observations, and incidents through operator-visible endpoints and routes.

**Independent Test**: Query `/token-sync/status`, `/token-sync/sources`, and `/token-sync/incidents`, then verify state transitions and timestamps update after normal sync and induced drift.

- [x] T018 [US3] Implement status API deployment values in `kubernetes/apps/observability/token-sync-status/app/helmrelease.yaml` to serve contract endpoints
- [x] T019 [P] [US3] Configure status API route exposure in `kubernetes/apps/observability/token-sync-status/app/httproute.yaml` behind `envoy-oauth`
- [x] T020 [P] [US3] Align API payload schemas with contract definitions in `specs/001-fix-headlamp-token-sync/contracts/token-sync.openapi.yaml`
- [x] T021 [US3] Register status API resources in `kubernetes/apps/observability/token-sync-status/app/kustomization.yaml` and `kubernetes/apps/observability/token-sync-status/ks.yaml`
- [x] T022 [US3] Add US3 endpoint verification and remediation checks to `specs/001-fix-headlamp-token-sync/quickstart.md`

**Checkpoint**: Operators can observe health and incidents without ad-hoc log inspection.

______________________________________________________________________

## Final Phase: Polish & Cross-Cutting Concerns

**Purpose**: Complete documentation, validation, and delivery readiness.

- [x] T023 [P] Update feature handoff notes and measurable outcomes mapping in `specs/001-fix-headlamp-token-sync/plan.md`
- [x] T024 [P] Update post-merge validation runbook for token-sync checks in `docs/POST-MERGE-VERIFICATION.md`
- [x] T025 Run `task lint` from repository root and fix any formatting issues across changed files
- [x] T026 Run `task dev:validate` from repository root and confirm flux-local renders all resources successfully

______________________________________________________________________

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies.
- **Foundational (Phase 2)**: Depends on Phase 1 and blocks all user story work.
- **US1 (Phase 3)**: Depends on Foundational completion.
- **US2 (Phase 4)**: Depends on Foundational completion and can start after US1 if using US1 rotation behavior as baseline.
- **US3 (Phase 5)**: Depends on Foundational completion and US2 state model for incident/status exposure.
- **Polish (Final)**: Depends on completion of selected user stories.

### User Story Dependencies

- **US1 (P1)**: Independent after Foundational.
- **US2 (P2)**: Independent after Foundational, but operationally benefits from US1 rotation controls.
- **US3 (P3)**: Depends on US2 incident/state artifacts to expose meaningful visibility.

### Parallel Opportunities

- T002 and T003 can run in parallel.
- T005, T006, T007, and T008 can run in parallel after T004.
- In US1, T010 can run in parallel with T009.
- In US2, T014 and T015 can run in parallel with T013.
- In US3, T019 and T020 can run in parallel with T018.
- In Final Phase, T023 and T024 can run in parallel before validation tasks.

______________________________________________________________________

## Parallel Example: User Story 1

```bash
Task: "Set refreshInterval and target policy in kubernetes/apps/observability/headlamp/app/externalsecret.yaml"
Task: "Ensure reloader annotations in kubernetes/apps/observability/headlamp/app/helmrelease.yaml"
```

## Parallel Example: User Story 2

```bash
Task: "Implement sync-check execution in kubernetes/apps/observability/headlamp/app/token-sync-cronjob.yaml"
Task: "Add conflict incident state template in kubernetes/apps/observability/headlamp/app/token-sync-configmap.yaml"
Task: "Update precedence metadata notes in specs/001-fix-headlamp-token-sync/research.md"
```

## Parallel Example: User Story 3

```bash
Task: "Implement status API values in kubernetes/apps/observability/token-sync-status/app/helmrelease.yaml"
Task: "Configure API route in kubernetes/apps/observability/token-sync-status/app/httproute.yaml"
Task: "Align schema in specs/001-fix-headlamp-token-sync/contracts/token-sync.openapi.yaml"
```

______________________________________________________________________

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (Setup).
2. Complete Phase 2 (Foundational).
3. Complete Phase 3 (US1).
4. Validate rotation behavior with quickstart criteria.

### Incremental Delivery

1. Deliver US1 for immediate login reliability gains.
2. Deliver US2 for deterministic conflict handling and incident capture.
3. Deliver US3 for operator visibility endpoints and monitoring workflows.
4. Run final validation and update runbooks.

### Suggested MVP Scope

- **MVP**: Through Phase 3 (US1) plus validation tasks T025-T026.
- **Post-MVP**: US2 and US3 in subsequent increments.
