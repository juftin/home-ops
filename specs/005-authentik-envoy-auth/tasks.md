# Tasks: Authentik Cluster Authentication

**Input**: Design documents from `/specs/005-authentik-envoy-auth/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Not explicitly requested in the specification; this task list focuses on implementation and validation via existing repo gates.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare migration inventory and bootstrap structure for a new Authentik app.

- [x] T001 Create pilot route inventory in /Users/juftin/git/home-ops/specs/005-authentik-envoy-auth/files/pilot-routes.yaml
- [x] T002 [P] Create auth-path assignment matrix in /Users/juftin/git/home-ops/specs/005-authentik-envoy-auth/files/auth-path-matrix.yaml
- [x] T003 [P] Create Authentik bootstrap values notes in /Users/juftin/git/home-ops/specs/005-authentik-envoy-auth/files/authentik-bootstrap.yaml
- [x] T004 [P] Update quickstart pre-reqs for first-time Authentik install in /Users/juftin/git/home-ops/specs/005-authentik-envoy-auth/quickstart.md

______________________________________________________________________

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Stand up Authentik and baseline gateway policy before any user story implementation.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T005 Create security namespace manifest in /Users/juftin/git/home-ops/kubernetes/apps/security/namespace.yaml
- [x] T006 Create security namespace kustomization in /Users/juftin/git/home-ops/kubernetes/apps/security/kustomization.yaml
- [x] T007 Create Authentik Flux kustomization in /Users/juftin/git/home-ops/kubernetes/apps/security/authentik/ks.yaml
- [x] T008 [P] Create Authentik app kustomization in /Users/juftin/git/home-ops/kubernetes/apps/security/authentik/app/kustomization.yaml
- [x] T009 [P] Create Authentik OCIRepository source in /Users/juftin/git/home-ops/kubernetes/apps/security/authentik/app/ocirepository.yaml
- [x] T010 Create Authentik HelmRelease with ingress host config in /Users/juftin/git/home-ops/kubernetes/apps/security/authentik/app/helmrelease.yaml
- [x] T011 [P] Create Authentik ExternalSecret references in /Users/juftin/git/home-ops/kubernetes/apps/security/authentik/app/externalsecret.yaml
- [x] T012 [P] Register security namespace apps in cluster app tree at /Users/juftin/git/home-ops/kubernetes/flux/cluster/cluster-apps.yaml
- [x] T013 Define Authentik gateway SecurityPolicy values in /Users/juftin/git/home-ops/kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml
- [x] T014 [P] Define internal Authentik gateway SecurityPolicy values in /Users/juftin/git/home-ops/kubernetes/apps/network/envoy-gateway/app/oauth-policy-internal.sops.yaml
- [x] T015 [P] Add Authentik OAuth client secret reference in /Users/juftin/git/home-ops/kubernetes/apps/network/envoy-gateway/app/oauth-client-secret.sops.yaml
- [x] T016 Add explicit Authentik and oauth callback ingress ordering in /Users/juftin/git/home-ops/kubernetes/apps/network/cloudflare-tunnel/app/helmrelease.yaml
- [x] T017 [P] Ensure oauth utility routes stay public in /Users/juftin/git/home-ops/kubernetes/apps/default/oauth-pages/app/securitypolicy.yaml
- [x] T018 [P] Ensure oauth denied/logout host coverage in /Users/juftin/git/home-ops/kubernetes/apps/default/oauth-pages/app/httproute.yaml

**Checkpoint**: Authentik is deployed and base gateway/auth routing is ready.

______________________________________________________________________

## Phase 3: User Story 1 - Access protected apps with Authentik (Priority: P1) 🎯 MVP

**Goal**: Users can authenticate through newly deployed Authentik and access pilot protected routes through envoy-oauth.

**Independent Test**: Access a pilot protected hostname while signed out, complete Authentik login, and verify return to requested route.

### Implementation for User Story 1

- [x] T019 [US1] Configure envoy auth listener/policy attachment in /Users/juftin/git/home-ops/kubernetes/apps/network/envoy-gateway/app/envoy.yaml
- [x] T020 [P] [US1] Move Headlamp route to envoy-oauth parentRef in /Users/juftin/git/home-ops/kubernetes/apps/observability/headlamp/app/httproute.yaml
- [x] T021 [P] [US1] Move Grafana route to envoy-oauth parentRef in /Users/juftin/git/home-ops/kubernetes/apps/observability/kube-prometheus-stack/app/httproute.yaml
- [x] T022 [US1] Record pilot migration phase updates in /Users/juftin/git/home-ops/specs/005-authentik-envoy-auth/files/pilot-routes.yaml
- [x] T023 [US1] Align Authentik redirect and callback host mapping in /Users/juftin/git/home-ops/kubernetes/apps/network/cloudflare-tunnel/app/helmrelease.yaml

**Checkpoint**: User Story 1 is independently functional and demoable.

______________________________________________________________________

## Phase 4: User Story 2 - Keep Google SSO alternative available (Priority: P2)

**Goal**: Non-pilot routes continue using Google-proxy authentication while Authentik serves pilot routes.

**Independent Test**: Confirm one pilot route authenticates via Authentik and one non-pilot route still authenticates via Google-proxy.

### Implementation for User Story 2

- [x] T024 [US2] Declare non-pilot route assignments to google-proxy in /Users/juftin/git/home-ops/specs/005-authentik-envoy-auth/files/auth-path-matrix.yaml
- [x] T025 [P] [US2] Keep wildcard non-pilot traffic routed to envoy-external in /Users/juftin/git/home-ops/kubernetes/apps/network/cloudflare-tunnel/app/helmrelease.yaml
- [x] T026 [P] [US2] Verify oauth-pages callback compatibility for Google-proxy paths in /Users/juftin/git/home-ops/kubernetes/apps/default/oauth-pages/app/httproute.yaml
- [x] T027 [US2] Preserve Google-proxy behavior for non-migrated routes in /Users/juftin/git/home-ops/kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml
- [x] T028 [US2] Update rollback guidance for mixed auth-path mode in /Users/juftin/git/home-ops/specs/005-authentik-envoy-auth/quickstart.md

**Checkpoint**: User Stories 1 and 2 both work independently.

______________________________________________________________________

## Phase 5: User Story 3 - Operate and audit auth behavior (Priority: P3)

**Goal**: Administrators can identify auth path and outcomes for troubleshooting with 30-day queryability.

**Independent Test**: For successful and denied requests, operators can identify route, auth path, outcome, and timestamp from observable records.

### Implementation for User Story 3

- [x] T029 [US3] Add auth outcome signal fields in /Users/juftin/git/home-ops/kubernetes/apps/network/envoy-gateway/app/envoy.yaml
- [x] T030 [P] [US3] Verify auth metrics scrape coverage in /Users/juftin/git/home-ops/kubernetes/apps/network/envoy-gateway/app/podmonitor.yaml
- [x] T031 [P] [US3] Document 30-day auth outcome query procedure in /Users/juftin/git/home-ops/specs/005-authentik-envoy-auth/quickstart.md
- [x] T032 [US3] Add outage diagnosis steps for unavailable auth-path in /Users/juftin/git/home-ops/specs/005-authentik-envoy-auth/research.md

**Checkpoint**: All user stories are independently functional.

______________________________________________________________________

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final consistency, validation, and readiness for PR.

- [x] T033 [P] Normalize route/auth terminology in /Users/juftin/git/home-ops/specs/005-authentik-envoy-auth/spec.md
- [x] T034 [P] Validate contract-doc parity in /Users/juftin/git/home-ops/specs/005-authentik-envoy-auth/contracts/auth-routing.openapi.yaml
- [x] T035 Run repository validation gates and capture results in /Users/juftin/git/home-ops/specs/005-authentik-envoy-auth/quickstart.md
- [x] T036 Prepare PR readiness summary in /Users/juftin/git/home-ops/specs/005-authentik-envoy-auth/plan.md
- [x] T037 [P] Add Authentik app entry in /Users/juftin/git/home-ops/README.md
- [x] T038 [P] Add security/authentik architecture coverage in /Users/juftin/git/home-ops/docs/ARCHITECTURE.md

______________________________________________________________________

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies.
- **Foundational (Phase 2)**: Depends on Setup completion; blocks all user stories.
- **User Story phases (Phase 3-5)**: Depend on Foundational completion.
- **Polish (Phase 6)**: Depends on completion of desired user stories.

### User Story Dependencies

- **US1 (P1)**: Starts after Phase 2; no dependency on other stories.
- **US2 (P2)**: Starts after Phase 2; depends only on shared foundation.
- **US3 (P3)**: Starts after Phase 2; depends on shared foundation and traffic from US1/US2.

### Dependency Graph

- Phase 1 -> Phase 2 -> {Phase 3, Phase 4, Phase 5} -> Phase 6
- Story order for incremental delivery: US1 -> US2 -> US3

### Parallel Opportunities

- **Phase 1**: T002, T003, T004 can run in parallel after T001.
- **Phase 2**: T008, T009, T011, T012, T014, T015, T017, T018 can run in parallel once T005-T007 and T010 are in place.
- **US1**: T020 and T021 can run in parallel after T019.
- **US2**: T025 and T026 can run in parallel after T024.
- **US3**: T030 and T031 can run in parallel after T029.

______________________________________________________________________

## Parallel Example: User Story 1

```bash
Task: "T020 [US1] Move Headlamp route to envoy-oauth parentRef in /Users/juftin/git/home-ops/kubernetes/apps/observability/headlamp/app/httproute.yaml"
Task: "T021 [US1] Move Grafana route to envoy-oauth parentRef in /Users/juftin/git/home-ops/kubernetes/apps/observability/kube-prometheus-stack/app/httproute.yaml"
```

## Parallel Example: User Story 2

```bash
Task: "T025 [US2] Keep wildcard non-pilot traffic routed to envoy-external in /Users/juftin/git/home-ops/kubernetes/apps/network/cloudflare-tunnel/app/helmrelease.yaml"
Task: "T026 [US2] Verify oauth-pages callback compatibility for Google-proxy paths in /Users/juftin/git/home-ops/kubernetes/apps/default/oauth-pages/app/httproute.yaml"
```

## Parallel Example: User Story 3

```bash
Task: "T030 [US3] Verify auth metrics scrape coverage in /Users/juftin/git/home-ops/kubernetes/apps/network/envoy-gateway/app/podmonitor.yaml"
Task: "T031 [US3] Document 30-day auth outcome query procedure in /Users/juftin/git/home-ops/specs/005-authentik-envoy-auth/quickstart.md"
```

______________________________________________________________________

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 and Phase 2 (includes Authentik deployment).
2. Complete Phase 3 (US1).
3. Validate US1 independently before expanding scope.

### Incremental Delivery

1. Deliver US1 (pilot Authentik access).
2. Deliver US2 (parallel Google-proxy continuity).
3. Deliver US3 (operational auditability).
4. Finish Phase 6 polish and validation gates.

### Suggested MVP Scope

- **MVP**: Phase 1 + Phase 2 + Phase 3 (US1), including initial Authentik stand-up.
- **Post-MVP**: US2 and US3 in parallel or sequential execution.

______________________________________________________________________

## Notes

- All tasks follow required checklist format with checkbox, Task ID, optional [P], required [USx] in story phases, and absolute file path.
- Story tasks remain independently testable per the independent test criteria in each phase.
