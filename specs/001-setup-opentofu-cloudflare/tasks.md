# Tasks: OpenTofu Cloudflare IaC Foundation

**Input**: Design documents from `/Users/juftin/git/home-ops/worktrees/iac/specs/001-setup-opentofu-cloudflare/`
**Prerequisites**: `/Users/juftin/git/home-ops/worktrees/iac/specs/001-setup-opentofu-cloudflare/plan.md`, `/Users/juftin/git/home-ops/worktrees/iac/specs/001-setup-opentofu-cloudflare/spec.md`, `/Users/juftin/git/home-ops/worktrees/iac/specs/001-setup-opentofu-cloudflare/research.md`, `/Users/juftin/git/home-ops/worktrees/iac/specs/001-setup-opentofu-cloudflare/data-model.md`, `/Users/juftin/git/home-ops/worktrees/iac/specs/001-setup-opentofu-cloudflare/contracts/iac-foundation.openapi.yaml`

**Tests**: No explicit TDD/test-first requirement was specified in the feature spec; validation tasks focus on repository and IaC command checks.

**Organization**: Tasks are grouped by user story to enable independent implementation and validation of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- All task descriptions include exact file paths

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize shared files and task wiring needed by all stories.

- [ ] T001 Create IaC root README scaffold in `/Users/juftin/git/home-ops/worktrees/iac/iac/README.md`
- [ ] T002 Create IaC task namespace file in `/Users/juftin/git/home-ops/worktrees/iac/.taskfiles/iac/Taskfile.yaml`
- [ ] T003 [P] Add `iac` include entry in `/Users/juftin/git/home-ops/worktrees/iac/Taskfile.yaml`

______________________________________________________________________

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core prerequisites that MUST be complete before any user story work.

**⚠️ CRITICAL**: No user story work starts until this phase is complete.

- [ ] T004 Add OpenTofu tool pin in `/Users/juftin/git/home-ops/worktrees/iac/.mise.toml`
- [ ] T005 Implement baseline IaC commands (`fmt`, `validate`) in `/Users/juftin/git/home-ops/worktrees/iac/.taskfiles/iac/Taskfile.yaml`
- [ ] T006 Add OpenTofu/Terraform state and cache ignore rules in `/Users/juftin/git/home-ops/worktrees/iac/iac/.gitignore`
- [ ] T007 Update IaC development guardrails section in `/Users/juftin/git/home-ops/worktrees/iac/AGENTS.md`

**Checkpoint**: Foundation ready — user stories can now proceed.

______________________________________________________________________

## Phase 3: User Story 1 - Establish baseline IaC layout (Priority: P1) 🎯 MVP

**Goal**: Deliver the initial Cloudflare category layout under `iac/live` and `iac/modules` with clear ownership boundaries.

**Independent Test**: Confirm `iac/live` and `iac/modules` exist, `cloudflare` exists in both paths, and documentation explicitly states reusable-vs-live ownership.

- [ ] T008 [US1] Create category directory tree in `/Users/juftin/git/home-ops/worktrees/iac/iac/live/cloudflare/homelab/` and `/Users/juftin/git/home-ops/worktrees/iac/iac/modules/cloudflare/zone-baseline/`
- [ ] T009 [P] [US1] Create module scaffold files in `/Users/juftin/git/home-ops/worktrees/iac/iac/modules/cloudflare/zone-baseline/main.tf`, `/Users/juftin/git/home-ops/worktrees/iac/iac/modules/cloudflare/zone-baseline/variables.tf`, `/Users/juftin/git/home-ops/worktrees/iac/iac/modules/cloudflare/zone-baseline/outputs.tf`, and `/Users/juftin/git/home-ops/worktrees/iac/iac/modules/cloudflare/zone-baseline/versions.tf`
- [ ] T010 [P] [US1] Create live stack scaffold files in `/Users/juftin/git/home-ops/worktrees/iac/iac/live/cloudflare/homelab/main.tf`, `/Users/juftin/git/home-ops/worktrees/iac/iac/live/cloudflare/homelab/providers.tf`, `/Users/juftin/git/home-ops/worktrees/iac/iac/live/cloudflare/homelab/backend.tf`, `/Users/juftin/git/home-ops/worktrees/iac/iac/live/cloudflare/homelab/variables.tf`, and `/Users/juftin/git/home-ops/worktrees/iac/iac/live/cloudflare/homelab/outputs.tf`
- [ ] T011 [US1] Document `live/` vs `modules/` ownership boundaries in `/Users/juftin/git/home-ops/worktrees/iac/iac/README.md`
- [ ] T012 [US1] Add IaC structure overview for Cloudflare category in `/Users/juftin/git/home-ops/worktrees/iac/docs/ARCHITECTURE.md`

**Checkpoint**: User Story 1 is independently complete and verifiable.

______________________________________________________________________

## Phase 4: User Story 2 - Bootstrap tools consistently (Priority: P2)

**Goal**: Ensure contributors can install and run the IaC toolchain using existing mise-based workflows.

**Independent Test**: On a clean workstation, run bootstrap instructions and execute first IaC validation command successfully without manual version selection.

- [ ] T013 [US2] Add IaC bootstrap command flow to `/Users/juftin/git/home-ops/worktrees/iac/docs/TASKS.md`
- [ ] T014 [P] [US2] Create onboarding guide in `/Users/juftin/git/home-ops/worktrees/iac/docs/IAC-SETUP.md`
- [ ] T015 [US2] Document `task iac:*` command usage in `/Users/juftin/git/home-ops/worktrees/iac/docs/TASKS.md` and `/Users/juftin/git/home-ops/worktrees/iac/iac/README.md`
- [ ] T016 [US2] Add partially-installed-tool troubleshooting guidance in `/Users/juftin/git/home-ops/worktrees/iac/docs/IAC-SETUP.md`

**Checkpoint**: User Story 2 is independently complete and verifiable.

______________________________________________________________________

## Phase 5: User Story 3 - Prepare reusable Cloudflare-first workflow (Priority: P3)

**Goal**: Demonstrate reusable module design and live-stack composition for Cloudflare, with clear expansion guidance for future categories.

**Independent Test**: Verify live stack consumes module outputs/inputs (no duplicate resource definitions) and documentation explains how to add a second category without restructuring Cloudflare paths.

- [ ] T017 [US3] Implement reusable Cloudflare module interfaces in `/Users/juftin/git/home-ops/worktrees/iac/iac/modules/cloudflare/zone-baseline/main.tf`, `/Users/juftin/git/home-ops/worktrees/iac/iac/modules/cloudflare/zone-baseline/variables.tf`, and `/Users/juftin/git/home-ops/worktrees/iac/iac/modules/cloudflare/zone-baseline/outputs.tf`
- [ ] T018 [US3] Wire live homelab stack module consumption in `/Users/juftin/git/home-ops/worktrees/iac/iac/live/cloudflare/homelab/main.tf`
- [ ] T019 [P] [US3] Define provider/backend constraints in `/Users/juftin/git/home-ops/worktrees/iac/iac/live/cloudflare/homelab/providers.tf` and `/Users/juftin/git/home-ops/worktrees/iac/iac/live/cloudflare/homelab/backend.tf`
- [ ] T020 [P] [US3] Add example non-secret variable file in `/Users/juftin/git/home-ops/worktrees/iac/iac/live/cloudflare/homelab/terraform.tfvars.example`
- [ ] T021 [US3] Document future category expansion pattern in `/Users/juftin/git/home-ops/worktrees/iac/iac/README.md` and `/Users/juftin/git/home-ops/worktrees/iac/docs/ARCHITECTURE.md`

**Checkpoint**: User Story 3 is independently complete and verifiable.

______________________________________________________________________

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final consistency, validation, and release readiness across all stories.

- [ ] T022 [P] Run repository lint and formatting checks from `/Users/juftin/git/home-ops/worktrees/iac/` using `task lint`
- [ ] T023 [P] Run IaC validation commands from `/Users/juftin/git/home-ops/worktrees/iac/iac/` via `/Users/juftin/git/home-ops/worktrees/iac/.taskfiles/iac/Taskfile.yaml`
- [ ] T024 Run Flux manifest validation from `/Users/juftin/git/home-ops/worktrees/iac/` using `task dev:validate`
- [ ] T025 Perform final docs consistency pass in `/Users/juftin/git/home-ops/worktrees/iac/README.md`, `/Users/juftin/git/home-ops/worktrees/iac/AGENTS.md`, and `/Users/juftin/git/home-ops/worktrees/iac/docs/TASKS.md`

______________________________________________________________________

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies; starts immediately.
- **Phase 2 (Foundational)**: Depends on Phase 1; blocks all user stories.
- **Phase 3 (US1)**: Depends on Phase 2.
- **Phase 4 (US2)**: Depends on Phase 2.
- **Phase 5 (US3)**: Depends on Phase 2 and US1 directory scaffolding.
- **Phase 6 (Polish)**: Depends on completion of all selected user stories.

### User Story Dependency Graph

- **US1 (P1)**: Starts after Foundational; no dependency on other user stories.
- **US2 (P2)**: Starts after Foundational; independent of US1/US3 implementation details.
- **US3 (P3)**: Starts after Foundational and requires US1 layout scaffolding.

### Within Each User Story

- Structure/scaffold tasks before composition tasks.
- Module definitions before live stack wiring.
- Story documentation updates after core implementation tasks.
- Story must pass independent test criteria before moving to next priority.

### Parallel Opportunities

- Phase 1: `T003` can run in parallel with `T001`/`T002`.
- Phase 3 (US1): `T009` and `T010` can run in parallel after `T008`.
- Phase 4 (US2): `T014` can run in parallel with `T013`.
- Phase 5 (US3): `T019` and `T020` can run in parallel after `T018`.
- Phase 6: `T022` and `T023` can run in parallel before `T024`.

______________________________________________________________________

## Parallel Example: User Story 1

```bash
# After T008 creates directory tree:
Task: "T009 [US1] Create module scaffold files in /Users/juftin/git/home-ops/worktrees/iac/iac/modules/cloudflare/zone-baseline/"
Task: "T010 [US1] Create live stack scaffold files in /Users/juftin/git/home-ops/worktrees/iac/iac/live/cloudflare/homelab/"
```

## Parallel Example: User Story 2

```bash
# After foundational tooling tasks:
Task: "T013 [US2] Add IaC bootstrap command flow in /Users/juftin/git/home-ops/worktrees/iac/docs/TASKS.md"
Task: "T014 [US2] Create /Users/juftin/git/home-ops/worktrees/iac/docs/IAC-SETUP.md"
```

## Parallel Example: User Story 3

```bash
# After live stack module wiring in T018:
Task: "T019 [US3] Define provider/backend constraints in /Users/juftin/git/home-ops/worktrees/iac/iac/live/cloudflare/homelab/"
Task: "T020 [US3] Add terraform.tfvars.example in /Users/juftin/git/home-ops/worktrees/iac/iac/live/cloudflare/homelab/"
```

______________________________________________________________________

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (Setup).
2. Complete Phase 2 (Foundational).
3. Complete Phase 3 (US1).
4. Validate US1 independent test criteria and baseline validations.
5. Pause for review before expanding scope.

### Incremental Delivery

1. Setup + Foundational establishes shared platform.
2. Deliver US1 (baseline structure).
3. Deliver US2 (bootstrap workflow docs/commands).
4. Deliver US3 (reusable module + live composition pattern).
5. Finish with Polish phase validations and documentation consistency.

### Parallel Team Strategy

1. Team completes Phases 1 and 2 together.
2. Then parallelize:
   - Engineer A: US1
   - Engineer B: US2
3. Engineer C starts US3 after US1 scaffolding checkpoint is met.
4. Rejoin for Phase 6 validation and release readiness.

______________________________________________________________________

## Notes

- `[P]` tasks are designed for different files and minimal cross-dependencies.
- `[US#]` labels map each implementation task to a specific user story.
- Task order preserves independent testability for each story.
- Suggested MVP scope is Phase 3 (US1) after Setup + Foundational completion.
