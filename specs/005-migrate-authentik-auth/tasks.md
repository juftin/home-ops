# Tasks: Envoy Authentik Authentication Migration

**Input**: Design documents from `/specs/005-migrate-authentik-auth/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: No explicit TDD/contract-first requirement was requested in the specification; validation tasks are included per story.

**Organization**: Tasks are grouped by user story to enable independent implementation and validation.

## Format: `[ID] [P?] [Story] Description`

______________________________________________________________________

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare shared configuration and documentation touchpoints for implementation.

- [ ] T001 Document Authentik migration scope and operator prechecks in specs/005-migrate-authentik-auth/quickstart.md
- [ ] T002 [P] Record auth-mode implementation assumptions in specs/005-migrate-authentik-auth/research.md
- [ ] T003 [P] Define endpoint and decision payload expectations in specs/005-migrate-authentik-auth/contracts/auth-mode-management.openapi.yaml

______________________________________________________________________

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish cluster-wide auth foundations that block all user stories until complete.

- [ ] T004 Add cluster-wide authentication mode values and defaults in kubernetes/apps/network/envoy-gateway/app/helmrelease.yaml
- [ ] T005 [P] Add Authentik external authorization provider wiring in kubernetes/apps/network/envoy-gateway/app/envoy.yaml
- [ ] T006 [P] Update Envoy OAuth policy resources for centralized decision enforcement in kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml
- [ ] T007 [P] Update internal OAuth policy resource parity in kubernetes/apps/network/envoy-gateway/app/oauth-policy-internal.sops.yaml
- [ ] T008 Ensure foundational resources are referenced consistently in kubernetes/apps/network/envoy-gateway/app/kustomization.yaml

**Checkpoint**: Foundation ready - user story implementation can now begin.

______________________________________________________________________

## Phase 3: User Story 1 - Centralized authentication flow (Priority: P1) 🎯 MVP

**Goal**: Route protected authentication/authorization decisions through Authentik with fail-closed behavior.

**Independent Test**: Access a protected route with (a) valid user/group and (b) missing group, and confirm Authentik-based allow/deny outcomes are enforced.

### Implementation for User Story 1

- [ ] T009 [US1] Configure Envoy auth flow routing to Authentik decision path in kubernetes/apps/network/envoy-gateway/app/envoy.yaml
- [ ] T010 [P] [US1] Configure Authentik-backed credential/secret mapping in kubernetes/apps/network/envoy-gateway/app/oauth-client-secret.sops.yaml
- [ ] T011 [P] [US1] Enforce group-based allow/deny claims mapping in kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml
- [ ] T012 [P] [US1] Mirror centralized auth behavior for internal gateway path in kubernetes/apps/network/envoy-gateway/app/oauth-policy-internal.sops.yaml
- [ ] T013 [US1] Ensure oauth callback and protected host routing reaches oauth gateway first in kubernetes/apps/network/cloudflare-tunnel/app/helmrelease.yaml
- [ ] T014 [US1] Validate US1 flow steps and expected outcomes in specs/005-migrate-authentik-auth/quickstart.md
- [ ] T015 [US1] Define explicit fail-closed deny behavior when Authentik/extAuth is unavailable in kubernetes/apps/network/envoy-gateway/app/envoy.yaml
- [ ] T016 [US1] Document fail-closed outage-path validation steps in specs/005-migrate-authentik-auth/quickstart.md

**Checkpoint**: User Story 1 is independently functional and verifiable.

______________________________________________________________________

## Phase 4: User Story 2 - Interchangeable auth mode (Priority: P2)

**Goal**: Support safe cluster-wide switching between Authentik mode and legacy mode.

**Independent Test**: Switch mode Authentik → legacy → Authentik and confirm all protected routes follow the selected mode without route-level edits.

### Implementation for User Story 2

- [ ] T017 [US2] Implement explicit cluster-wide auth mode selector behavior in kubernetes/apps/network/envoy-gateway/app/helmrelease.yaml
- [ ] T018 [US2] Add legacy fallback routing behavior without protected-route intent drift in kubernetes/apps/network/envoy-gateway/app/envoy.yaml
- [ ] T019 [P] [US2] Update denied/logged-out route compatibility for both modes in kubernetes/apps/default/oauth-pages/app/httproute.yaml
- [ ] T020 [US2] Add rollback and mode-switch operator steps in specs/005-migrate-authentik-auth/quickstart.md
- [ ] T021 [US2] Define Terraform-transition auth-mode invariants and non-behavioral constraints in specs/005-migrate-authentik-auth/plan.md
- [ ] T022 [US2] Document Terraform ownership boundaries for auth resources in specs/005-migrate-authentik-auth/research.md

**Checkpoint**: User Story 2 is independently functional and verifiable.

______________________________________________________________________

## Phase 5: User Story 3 - Operational continuity and auditability (Priority: P3)

**Goal**: Provide observable allow/deny outcomes with sufficient context for incident response.

**Independent Test**: Generate allow and deny requests, then verify operators can identify timestamp, user identity, route, decision, and denial reason.

### Implementation for User Story 3

- [ ] T023 [US3] Emit/retain required auth decision fields in gateway behavior configuration at kubernetes/apps/network/envoy-gateway/app/envoy.yaml
- [ ] T024 [P] [US3] Add/adjust metrics and scrape coverage for auth outcome visibility in kubernetes/apps/network/envoy-gateway/app/podmonitor.yaml
- [ ] T025 [P] [US3] Document operator verification workflow for decision evidence in docs/POST-MERGE-VERIFICATION.md
- [ ] T026 [US3] Document security incident handling updates for deny and revocation cases in docs/SECURITYPOLICY-CHANGE-PLAYBOOK.md
- [ ] T027 [US3] Define SC-003 measurement method and evidence collection for 95% investigations within 10 minutes in docs/POST-MERGE-VERIFICATION.md

**Checkpoint**: User Story 3 is independently functional and verifiable.

______________________________________________________________________

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final consistency, documentation, and full-flow validation across stories.

- [ ] T028 [P] Align architecture documentation for Authentik-centered auth flow in docs/ARCHITECTURE.md
- [ ] T029 [P] Update feature summary and app/component references in README.md
- [ ] T030 Run full validation and branch-test checklist using specs/005-migrate-authentik-auth/quickstart.md

______________________________________________________________________

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies.
- **Phase 2 (Foundational)**: Depends on Phase 1; blocks all user stories.
- **Phase 3 (US1)**: Depends on Phase 2.
- **Phase 4 (US2)**: Depends on Phase 3 (builds on centralized auth behavior and adds mode switching).
- **Phase 5 (US3)**: Depends on Phase 3 (can proceed after centralized flow exists; may run in parallel with Phase 4 after T017 baseline).
- **Phase 6 (Polish)**: Depends on completion of targeted user stories.

### User Story Dependency Graph

- **US1 (P1)** → enables **US2 (P2)** and **US3 (P3)**
- **US2 (P2)** refines operational mode switching on top of US1
- **US3 (P3)** adds observability and incident readiness on top of US1

______________________________________________________________________

## Parallel Opportunities

- **Setup**: T002 and T003 can run in parallel.
- **Foundational**: T005, T006, and T007 can run in parallel after T004.
- **US1**: T010 and T011 can run in parallel after T009; T012 can run in parallel with T013 once policies are updated.
- **US2**: T019 can run in parallel with T018 after T017 defines mode selector behavior.
- **US3**: T024 and T025 can run in parallel after T023.
- **Polish**: T028 and T029 can run in parallel before T030.

### Parallel Example: User Story 1

```bash
Task: "Configure Authentik-backed credential/secret mapping in kubernetes/apps/network/envoy-gateway/app/oauth-client-secret.sops.yaml"
Task: "Enforce group-based allow/deny claims mapping in kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml"
```

### Parallel Example: User Story 2

```bash
Task: "Add legacy fallback routing behavior without protected-route intent drift in kubernetes/apps/network/envoy-gateway/app/envoy.yaml"
Task: "Update denied/logged-out route compatibility for both modes in kubernetes/apps/default/oauth-pages/app/httproute.yaml"
```

### Parallel Example: User Story 3

```bash
Task: "Add/adjust metrics and scrape coverage for auth outcome visibility in kubernetes/apps/network/envoy-gateway/app/podmonitor.yaml"
Task: "Document operator verification workflow for decision evidence in docs/POST-MERGE-VERIFICATION.md"
```

______________________________________________________________________

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 and Phase 2.
2. Complete Phase 3 (US1).
3. Validate US1 independently using the story test criteria.
4. Demo centralized Authentik decision flow before expanding scope.

### Incremental Delivery

1. Deliver US1 (centralized auth flow).
2. Deliver US2 (interchangeable mode switching).
3. Deliver US3 (operational observability/auditability).
4. Finish with Phase 6 polish and full validation.

### Parallel Team Strategy

1. Team completes Setup + Foundational together.
2. After US1 baseline, split work:
   - Engineer A: US2 mode switching
   - Engineer B: US3 observability and runbooks
3. Rejoin for polish and end-to-end validation.

______________________________________________________________________

## Notes

- All tasks follow the required checklist format with Task ID and file path.
- `[P]` marks tasks that can run concurrently without same-file conflicts.
- Story phases use `[US1]`, `[US2]`, `[US3]` labels for traceability.
