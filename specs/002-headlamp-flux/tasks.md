______________________________________________________________________

# Tasks: Headlamp + Flux Plugin

**Input**: Design documents from `/specs/002-headlamp-flux/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, quickstart.md ✅

**Organization**: Tasks are grouped by user story to enable independent implementation and
testing of each story. No tests requested — implementation tasks only.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

______________________________________________________________________

## Phase 1: Setup (Bring in Existing Work)

**Purpose**: Establish the starting point by merging the existing `headlamp-app` branch
manifests into the `002-headlamp-flux` feature branch.

- [ ] T001 Cherry-pick or copy existing headlamp manifests from `origin/headlamp-app` into `002-headlamp-flux` — files needed: `kubernetes/apps/observability/headlamp/app/helmrelease.yaml`, `kubernetes/apps/observability/headlamp/app/kustomization.yaml`, `kubernetes/apps/observability/headlamp/ks.yaml`, `kubernetes/apps/observability/kustomization.yaml`

**Checkpoint**: Existing HelmRelease, OCIRepository, and Flux Kustomization are present on the
feature branch and `task dev:validate` renders them without error.

______________________________________________________________________

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the RBAC resources that Headlamp requires before its pod can start.
The HelmRelease is configured with `serviceAccount.create: false` and
`clusterRoleBinding.create: false` — both must exist before Flux reconciles Headlamp.

**⚠️ CRITICAL**: Headlamp pod will crash-loop without these resources.

- [ ] T002 [P] Create ServiceAccount manifest at `kubernetes/apps/observability/headlamp/app/serviceaccount.yaml` — name: `headlamp-admin`, namespace: `observability`
- [ ] T003 [P] Create ClusterRoleBinding manifest at `kubernetes/apps/observability/headlamp/app/clusterrolebinding.yaml` — bind `headlamp-admin` ServiceAccount (in `observability`) to `cluster-admin` ClusterRole

**Checkpoint**: Both RBAC manifests exist and are syntactically valid YAML.

______________________________________________________________________

## Phase 3: User Story 1 — Access Cluster Dashboard (Priority: P1) 🎯 MVP

**Goal**: Headlamp is accessible at `https://headlamp.${SECRET_DOMAIN}` and a cluster
operator can log in with the admin token to browse cluster resources.

**Independent Test**: Navigate to `https://headlamp.juftin.dev`, paste the token from
1Password (`headlamp-admin-token → password field`), and verify that all cluster namespaces
and workloads are visible.

- [ ] T004 [P] [US1] Create HTTPRoute manifest at `kubernetes/apps/observability/headlamp/app/httproute.yaml` — hostname: `headlamp.${SECRET_DOMAIN}`, parentRef: `envoy-external` in `network` namespace, section: `https`, backendRef: service `headlamp` port `80`
- [ ] T005 [P] [US1] Update `kubernetes/apps/observability/headlamp/ks.yaml` — add `postBuild.substituteFrom` block referencing `cluster-secrets` Secret (required for `${SECRET_DOMAIN}` variable substitution in HTTPRoute hostname)
- [ ] T006 [US1] Update `kubernetes/apps/observability/headlamp/app/kustomization.yaml` — add `serviceaccount.yaml`, `clusterrolebinding.yaml`, and `httproute.yaml` to the `resources:` list (depends on T002, T003, T004)

**Checkpoint**: `task lint && task dev:validate` pass. US1 is fully deliverable: RBAC +
HTTPRoute + variable substitution are all in place.

______________________________________________________________________

## Phase 4: User Story 2 — Visualize Flux GitOps State (Priority: P2)

**Goal**: The Flux plugin surfaces Kustomizations, HelmReleases, GitRepositories, and their
sync/failure status inside Headlamp.

**Independent Test**: After logging in to Headlamp, open the Flux section and confirm all
Kustomizations and HelmReleases are listed with their current ready/failed status.

- [ ] T007 [US2] Review and confirm Flux plugin init container in `kubernetes/apps/observability/headlamp/app/helmrelease.yaml` — verify image `ghcr.io/headlamp-k8s/headlamp-plugin-flux:v0.4.0` with digest is present, `config.pluginsDir: /build/plugins` is set, and volume mounts are correct; update image tag/digest if a newer stable release is available

**Checkpoint**: The init container configuration is confirmed correct. No additional manifests
needed — the Flux plugin is fully implemented by the existing HelmRelease values.

______________________________________________________________________

## Phase 5: User Story 3 — Credentials Available via 1Password (Priority: P3)

**Goal**: The `headlamp-admin-token` item from 1Password is automatically synced into a
Kubernetes Secret in the `observability` namespace via ExternalSecret, so no manual secret
management is needed after initial deployment.

**Independent Test**: After Flux reconciles, `kubectl get secret headlamp-admin-token -n observability`
exists and its `password` field matches the value stored in 1Password under `headlamp-admin-token`.

- [ ] T008 [US3] Create ExternalSecret manifest at `kubernetes/apps/observability/headlamp/app/externalsecret.yaml` — secretStoreRef: `onepassword` (ClusterSecretStore), target secret name: `headlamp-admin-token`, dataFrom.extract.key: `headlamp-admin-token`
- [ ] T009 [US3] Update `kubernetes/apps/observability/headlamp/app/kustomization.yaml` — add `externalsecret.yaml` to the `resources:` list (depends on T008)

**Checkpoint**: All three user stories are independently functional. `task dev:validate`
renders all resources without error.

______________________________________________________________________

## Final Phase: Polish & Validation

**Purpose**: Formatting, offline validation, and PR preparation.

- [ ] T010 Run `task lint` to auto-fix YAML formatting across all new and modified files (run twice if first pass reports hook failures — second pass always succeeds)
- [ ] T011 Run `task dev:validate` to confirm offline rendering of all Flux HelmReleases and Kustomizations succeeds with no errors
- [ ] T012 Commit all changes with emoji prefix (e.g., `🔦 headlamp`) and push branch `002-headlamp-flux` to `origin`
- [ ] T013 Open pull request from `002-headlamp-flux` targeting `main` — include summary of new files and the `cluster-admin` justification from plan.md

______________________________________________________________________

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on T001 — blocks US1 pod startup
- **US1 (Phase 3)**: Depends on T002, T003 — HTTPRoute and ks.yaml update can start in parallel with Foundational
- **US2 (Phase 4)**: Depends on T001 only — review can happen any time after setup
- **US3 (Phase 5)**: Independent of US1/US2 — can start after T001
- **Polish (Final)**: Depends on T006, T007, T009

### User Story Dependencies

- **US1 (P1)**: Requires Foundational (T002, T003) + T004, T005, T006
- **US2 (P2)**: Requires T001 only — purely a review/confirm task
- **US3 (P3)**: Requires T001 only — independent of US1 and US2

### Parallel Opportunities

- T002 and T003 can run in parallel (different files)
- T004 and T005 can run in parallel (different files)
- T007 can run in parallel with any phase after T001
- T008 can run in parallel with Phase 3 tasks (different file)

______________________________________________________________________

## Parallel Example: US1 + US3 Simultaneously

```bash
# After T001 completes, all of these can launch together:
Task A: "Create serviceaccount.yaml"                   # T002
Task B: "Create clusterrolebinding.yaml"               # T003
Task C: "Create httproute.yaml"                        # T004
Task D: "Update ks.yaml with postBuild.substituteFrom" # T005
Task E: "Create externalsecret.yaml"                   # T008

# Once T002, T003, T004 complete:
Task F: "Update kustomization.yaml (SA + CRB + HTTPRoute)" # T006

# Once T008 completes:
Task G: "Update kustomization.yaml (add ExternalSecret)"   # T009
```

______________________________________________________________________

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Cherry-pick existing work (T001)
2. Complete Phase 2: RBAC — ServiceAccount + ClusterRoleBinding (T002, T003)
3. Complete Phase 3: HTTPRoute + ks.yaml update + kustomization update (T004–T006)
4. **STOP and VALIDATE**: `task lint && task dev:validate`
5. Headlamp is accessible at `https://headlamp.juftin.dev` ✅

### Incremental Delivery

1. T001 → T002/T003 → T004/T005 → T006 → **MVP: Headlamp accessible with full cluster RBAC**
2. T007 → **US2: Flux plugin confirmed working** (no new manifests needed)
3. T008 → T009 → **US3: Credentials auto-synced from 1Password**
4. T010 → T011 → T012 → T013 → **PR merged, Flux reconciles on main**

______________________________________________________________________

## Notes

- [P] tasks operate on different files — safe to run in parallel
- `task lint` auto-fixes YAML formatting with `yamlfmt` — always run before committing
- `task dev:validate` renders all Flux resources offline — no cluster access required
- The `cluster-admin` ClusterRoleBinding is a documented justified exception (see plan.md Complexity Tracking)
- If the 1Password field name for `headlamp-admin-token` differs from `password`, update the ExternalSecret `remoteRef.property` accordingly
- The `postBuild.substituteFrom` addition to `ks.yaml` (T005) is critical — without it `${SECRET_DOMAIN}` renders literally in the HTTPRoute hostname
