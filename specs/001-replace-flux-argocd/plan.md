# Implementation Plan: Replace Flux with ArgoCD

**Branch**: `001-replace-flux-argocd` | **Date**: 2026-03-15 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-replace-flux-argocd/spec.md`

## Summary

Replace Flux with ArgoCD as the sole GitOps controller by introducing ArgoCD bootstrap resources,
migrating ownership of all Flux-managed workloads in controlled waves, preserving SOPS-based secret
decryption, and codifying verification/rollback procedures. The rollout uses declarative Git-managed
resources and operational runbooks to satisfy full cutover, ArgoCD-only rollback, role-based access,
and per-wave disruption limits.

## Technical Context

**Language/Version**: YAML manifests, Bash scripts, Taskfile tasks (GitOps/IaC repository)
**Primary Dependencies**: Kubernetes, ArgoCD, Helmfile, Kustomize, SOPS + age, External Secrets Operator, Task
**Storage**: Kubernetes API resources in-cluster; encrypted Git-tracked secrets (`*.sops.yaml`)
**Testing**: `task lint`, `task dev:validate` (during transition), kustomize render validation, migration verification runbook checks
**Target Platform**: Talos Linux Kubernetes homelab cluster
**Project Type**: GitOps infrastructure repository
**Performance Goals**: Bootstrap reconciliation ready within 30 minutes; rollback restoration within 15 minutes; per-wave disruption \<=10 minutes
**Constraints**: Single-controller ownership after cutover; no plaintext secrets in Git; no manual production `kubectl apply`; reproducible from repository state
**Scale/Scope**: One homelab cluster; all workloads currently reconciled by Flux are in scope for migration

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Phase 0 Gate

| Principle                                      | Status | Notes                                                                              |
| ---------------------------------------------- | ------ | ---------------------------------------------------------------------------------- |
| I. GitOps & Declarative Infrastructure         | PASS   | Rollout is fully Git-declared; no out-of-band production mutations.                |
| II. IaC & Reproducibility                      | PASS   | Bootstrap and migration steps are documented and replayable from repository state. |
| III. Template & Bootstrappability              | PASS   | Quickstart/runbooks define end-to-end bootstrap and cutover behavior.              |
| IV. Modular Architecture                       | PASS   | ArgoCD design keeps per-namespace app ownership and dependency sequencing modular. |
| V. Code Quality, Readability & Design Patterns | PASS   | Reuses existing `kubernetes/apps` and Taskfile patterns with explicit naming.      |
| VI. DRY Principles                             | PASS   | Shared reconciliation patterns centralized through root ArgoCD definitions.        |
| VII. Observability & Failure Transparency      | PASS   | Plan requires explicit health/sync verification and actionable failure states.     |
| VIII. Security & Least Privilege               | PASS   | SOPS stays encrypted; role-based ArgoCD access enforces admin vs read-only scope.  |
| IX. Testing & Validation                       | PASS   | Validation gates remain mandatory (`task lint` + render/verification workflows).   |

### Post-Phase 1 Re-check

| Principle                                      | Status | Notes                                                                                                      |
| ---------------------------------------------- | ------ | ---------------------------------------------------------------------------------------------------------- |
| I. GitOps & Declarative Infrastructure         | PASS   | `contracts/rollout-api.openapi.yaml` and quickstart model all state transitions as declarative operations. |
| II. IaC & Reproducibility                      | PASS   | `research.md`, `data-model.md`, and `quickstart.md` define reproducible rollout behavior.                  |
| III. Template & Bootstrappability              | PASS   | Quickstart includes prerequisites, migration waves, verification, and rollback flow.                       |
| IV. Modular Architecture                       | PASS   | Data model preserves per-workload-group ownership and sequence controls.                                   |
| V. Code Quality, Readability & Design Patterns | PASS   | Design docs map directly to existing repo layout and conventions.                                          |
| VI. DRY Principles                             | PASS   | Contract/data model avoid duplicating app-specific logic; uses reusable workflow primitives.               |
| VII. Observability & Failure Transparency      | PASS   | Verification entity and contract require explicit health/sync/drift outcomes.                              |
| VIII. Security & Least Privilege               | PASS   | Access policy entity and role constraints are explicit and testable.                                       |
| IX. Testing & Validation                       | PASS   | Planning artifacts define offline + post-cutover validation gates.                                         |

**No constitution violations.**

## Project Structure

### Documentation (this feature)

```text
specs/001-replace-flux-argocd/
├── plan.md                    # This file
├── research.md                # Phase 0 output
├── data-model.md              # Phase 1 output
├── quickstart.md              # Phase 1 output
├── contracts/
│   └── rollout-api.openapi.yaml
└── tasks.md                   # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
bootstrap/
└── helmfile.d/
    ├── 01-apps.yaml                     # MODIFY: add ArgoCD bootstrap release and dependency order
    └── templates/
        └── values.yaml.gotmpl           # MODIFY: ArgoCD chart values, SOPS decryption integration, RBAC defaults

kubernetes/
├── apps/                                # EXISTING: source application manifests to be reconciled by ArgoCD
├── flux/
│   └── cluster/
│       └── ks.yaml                      # MODIFY/REMOVE during final Flux retirement wave
└── argocd/                              # NEW: ArgoCD root GitOps definitions
    ├── kustomization.yaml
    ├── appproject.yaml
    ├── applicationset.yaml
    └── rbac.yaml

scripts/
├── migrate-argocd-wave.sh               # NEW: orchestrates wave ownership transfer
├── verify-argocd-cutover.sh             # NEW: health/sync/drift verification
└── rollback-argocd-wave.sh              # NEW: ArgoCD-only rollback workflow

.taskfiles/
└── dev/
    └── Taskfile.yaml                    # MODIFY: add ArgoCD-focused validation helpers
```

**Structure Decision**: Keep the repository's existing GitOps layout and introduce a dedicated
`kubernetes/argocd/` root for ArgoCD control-plane resources. Preserve `kubernetes/apps/` as the
application source-of-truth while migrating reconciliation ownership from Flux to ArgoCD in waves.

## Complexity Tracking

No constitution violations requiring justification.
