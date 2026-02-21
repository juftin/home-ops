______________________________________________________________________

## description: "Task list for External Secrets Operator + 1Password integration"

# Tasks: External Secrets Operator with 1Password

**Input**: Design documents from `/specs/001-external-secrets-1password/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Not explicitly requested in spec - test tasks omitted per guidelines

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Path Conventions

All files created under `kubernetes/apps/external-secrets/` following the existing namespace pattern (cert-manager, network, etc.)

______________________________________________________________________

## Phase 1: Setup (Namespace Infrastructure)

**Purpose**: Create the external-secrets namespace structure following existing patterns

- [x] T001 Create namespace directory structure at kubernetes/apps/external-secrets/
- [x] T002 [P] Create Namespace resource in kubernetes/apps/external-secrets/namespace.yaml
- [x] T003 [P] Create namespace-level Kustomization in kubernetes/apps/external-secrets/kustomization.yaml

______________________________________________________________________

## Phase 2: Foundational (ESO Controller & CRDs)

**Purpose**: Deploy External Secrets Operator controller - MUST complete before 1Password Connect or any ExternalSecret can be created

**⚠️ CRITICAL**: No user story work can begin until ESO controller is running and CRDs are available

- [x] T004 Create ESO Flux Kustomization directory structure at kubernetes/apps/external-secrets/external-secrets/
- [x] T005 [P] Create ESO Flux Kustomization in kubernetes/apps/external-secrets/external-secrets/ks.yaml
- [x] T006 [P] Create ESO app directory at kubernetes/apps/external-secrets/external-secrets/app/
- [x] T007 [P] Create ESO OCIRepository in kubernetes/apps/external-secrets/external-secrets/app/ocirepository.yaml
- [x] T008 [P] Create ESO HelmRelease in kubernetes/apps/external-secrets/external-secrets/app/helmrelease.yaml
- [x] T009 [P] Create ESO app Kustomization in kubernetes/apps/external-secrets/external-secrets/app/kustomization.yaml

**Checkpoint**: ESO controller pods running, ExternalSecret and ClusterSecretStore CRDs available

______________________________________________________________________

## Phase 3: User Story 1 - ESO and 1Password Connect Running in Cluster (Priority: P1) 🎯 MVP

**Goal**: Deploy 1Password Connect server and establish ClusterSecretStore connectivity so the secret synchronization infrastructure exists

**Independent Test**: ESO controller and 1Password Connect pods reach ready state; ClusterSecretStore "onepassword" reports Ready: True

### Implementation for User Story 1

- [x] T010 [US1] Create 1Password Flux Kustomization directory structure at kubernetes/apps/external-secrets/onepassword/
- [x] T011 [P] [US1] Create 1Password Flux Kustomization in kubernetes/apps/external-secrets/onepassword/ks.yaml (with dependsOn: external-secrets)
- [x] T012 [P] [US1] Create 1Password app directory at kubernetes/apps/external-secrets/onepassword/app/
- [x] T013 [P] [US1] Create 1Password OCIRepository in kubernetes/apps/external-secrets/onepassword/app/ocirepository.yaml
- [x] T014 [US1] Create 1Password HelmRelease in kubernetes/apps/external-secrets/onepassword/app/helmrelease.yaml (two containers: api + sync, single replica)
- [x] T015 [P] [US1] Create bootstrap secret template in kubernetes/apps/external-secrets/onepassword/app/secret.sops.yaml
- [x] T016 [P] [US1] Create ClusterSecretStore in kubernetes/apps/external-secrets/onepassword/app/clustersecretstore.yaml
- [x] T017 [P] [US1] Create 1Password app Kustomization in kubernetes/apps/external-secrets/onepassword/app/kustomization.yaml

**Checkpoint**: 1Password Connect service running, ClusterSecretStore Ready: True - infrastructure functional, ready for application secrets

______________________________________________________________________

## Phase 4: User Story 2 - Adding a New App Secret via 1Password (Priority: P2)

**Goal**: Validate the end-to-end workflow by creating a test ExternalSecret that syncs from 1Password to Kubernetes

**Independent Test**: Create test item in 1Password "Kubernetes" vault, deploy ExternalSecret referencing it, confirm Kubernetes Secret appears with correct values within 60 seconds

### Implementation for User Story 2

- [x] T018 [P] [US2] Document ExternalSecret usage pattern in kubernetes/apps/external-secrets/README.md
- [x] T019 [US2] Validate ExternalSecret template contract from contracts/externalsecret-template.yaml works with deployed infrastructure
- [ ] T020 [US2] Execute quickstart.md workflow validation: create test 1Password item, test ExternalSecret, verify secret sync

**Checkpoint**: End-to-end workflow validated - any future app can add secrets via 1Password without SOPS tooling

______________________________________________________________________

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Documentation and validation of the complete feature

- [x] T021 [P] Update README.md Apps section to document external-secrets namespace
- [x] T022 [P] Update docs/ARCHITECTURE.md namespaces table to include external-secrets
- [x] T023 Run task lint validation (yamlfmt + pre-commit must pass)
- [x] T024 Run task dev:validate validation (flux-local render must pass)
- [x] T025 [P] Verify ServiceMonitor and Grafana dashboard are wired (resources created, inactive until monitoring stack deployed)

______________________________________________________________________

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User Story 1: Must complete before User Story 2 (US2 validates US1 infrastructure)
  - User Story 2: Validates end-to-end workflow, depends on US1
- **Polish (Final Phase)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2)
  - Deploys 1Password Connect server
  - Creates ClusterSecretStore
  - Blocks: User Story 2 (needs Connect infrastructure)
- **User Story 2 (P2)**: Can start after User Story 1 complete
  - Validates the secret sync workflow
  - Independent test: creates test secret, does not affect existing cluster operations

### Within Each Phase

- Setup: All tasks marked [P] can run in parallel
- Foundational: All tasks marked [P] can run in parallel (within Phase 2)
- User Story 1: Tasks T011-T017 can run in parallel after T010
- User Story 2: Tasks T018 and T019 can run in parallel, T020 must wait for both
- Polish: Tasks T021, T022, T025 can run in parallel; T023 and T024 are sequential validation

### Parallel Opportunities

**Phase 1 (Setup):**

```bash
# Launch T002 and T003 together:
Task: "Create Namespace resource in kubernetes/apps/external-secrets/namespace.yaml"
Task: "Create namespace-level Kustomization in kubernetes/apps/external-secrets/kustomization.yaml"
```

**Phase 2 (Foundational):**

```bash
# After T004-T006 (directory creation), launch T007-T009 together:
Task: "Create ESO OCIRepository in kubernetes/apps/external-secrets/external-secrets/app/ocirepository.yaml"
Task: "Create ESO HelmRelease in kubernetes/apps/external-secrets/external-secrets/app/helmrelease.yaml"
Task: "Create ESO app Kustomization in kubernetes/apps/external-secrets/external-secrets/app/kustomization.yaml"
```

**Phase 3 (User Story 1):**

```bash
# After T010 (directory creation), launch T011-T017 together:
Task: "Create 1Password Flux Kustomization in kubernetes/apps/external-secrets/onepassword/ks.yaml"
Task: "Create 1Password app directory at kubernetes/apps/external-secrets/onepassword/app/"
Task: "Create 1Password OCIRepository in kubernetes/apps/external-secrets/onepassword/app/ocirepository.yaml"
Task: "Create bootstrap secret template in kubernetes/apps/external-secrets/onepassword/app/secret.sops.yaml"
Task: "Create ClusterSecretStore in kubernetes/apps/external-secrets/onepassword/app/clustersecretstore.yaml"
Task: "Create 1Password app Kustomization in kubernetes/apps/external-secrets/onepassword/app/kustomization.yaml"
# T014 (HelmRelease) depends on T013 (OCIRepository) but can run with others
```

______________________________________________________________________

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Check ClusterSecretStore Ready status, pods healthy
5. Ready for secret sync (but not yet validated end-to-end)

### Complete Feature (Both User Stories)

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Infrastructure deployed → ClusterSecretStore Ready
3. Add User Story 2 → End-to-end validated → Feature complete and documented
4. Polish → Documentation updated, all validation passing

### Deployment Validation Sequence

**After User Story 1:**

```bash
kubectl get pods -n external-secrets
# Expect: external-secrets-* pod (ESO controller) Running
# Expect: onepassword-* pod (Connect api+sync) Running

kubectl get clustersecretstore onepassword
# Expect: Ready: True
```

**After User Story 2:**

```bash
# Follow quickstart.md validation workflow
# Create test 1Password item
# Create test ExternalSecret
# Verify Kubernetes Secret appears
# Verify secret updates propagate
```

______________________________________________________________________

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- User Story 1 is the MVP - delivers secret sync infrastructure
- User Story 2 validates the infrastructure works end-to-end
- All SOPS secrets remain unchanged throughout implementation
- Bootstrap secret (onepassword-secret) is the ONLY new SOPS file
- ESO chart: oci://ghcr.io/external-secrets/charts/external-secrets:2.0.1
- 1Password Connect chart: oci://ghcr.io/bjw-s-labs/helm/app-template:4.6.2
- Connect images: ghcr.io/1password/connect-api:1.8.1 + ghcr.io/1password/connect-sync:1.8.1
- ServiceMonitor + Grafana dashboard enabled on ESO (wired now, active when monitoring deployed)
- Single Connect replica, RollingUpdate strategy
- Validation: `task lint` then `task dev:validate` must pass before marking done
