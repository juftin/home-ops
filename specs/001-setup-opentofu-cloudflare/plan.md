# Implementation Plan: OpenTofu Cloudflare IaC Foundation

**Branch**: `001-setup-opentofu-cloudflare` | **Date**: 2026-03-15 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-setup-opentofu-cloudflare/spec.md`

## Summary

Establish a reproducible OpenTofu foundation under `iac/` using a `live/` + `modules/` model, with
`cloudflare` as the first category. Tool bootstrap stays aligned with existing `mise` conventions,
and validation follows repository quality gates. The design prioritizes reusable modules, clear
environment-specific stacks, and expansion to future categories without path restructuring.

## Technical Context

**Language/Version**: HCL for OpenTofu configuration; OpenTofu CLI managed by mise
**Primary Dependencies**: OpenTofu CLI, Cloudflare provider plugin, mise, Task, pre-commit
**Storage**: Remote OpenTofu state backend per live stack; no state files committed to Git
**Testing**: `task lint`, `tofu fmt -check -recursive`, `tofu validate`, plus existing `task dev:validate` for cluster manifests
**Target Platform**: macOS/Linux contributor workstations and CI runners
**Project Type**: Infrastructure-as-code foundation in existing monorepo
**Performance Goals**: Baseline Cloudflare stack validation completes in under 60 seconds on a standard contributor laptop
**Constraints**: Must keep plaintext secrets/state out of Git; must preserve existing repository workflows; must be category-extensible
**Scale/Scope**: Initial `cloudflare` category with one live stack (`homelab`) and reusable module pattern for future categories

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

| Principle                                      | Status  | Notes                                                 |
| ---------------------------------------------- | ------- | ----------------------------------------------------- |
| I. GitOps & Declarative Infrastructure         | ✅ Pass | IaC definitions are Git-managed artifacts             |
| II. Infrastructure-as-Code & Reproducibility   | ✅ Pass | Structure and workflows are fully repository-driven   |
| III. Template & Bootstrappability              | ✅ Pass | Setup uses existing mise bootstrap pattern            |
| IV. Modular Architecture                       | ✅ Pass | `modules/` vs `live/` establishes explicit separation |
| V. Code Quality, Readability & Design Patterns | ✅ Pass | Clear naming and directory conventions are defined    |
| VI. DRY Principles                             | ✅ Pass | Reusable logic centralized in modules                 |
| VII. Observability & Failure Transparency      | ✅ Pass | Validation flow is explicit and fail-fast             |
| VIII. Security & Least Privilege               | ✅ Pass | No plaintext secrets or state in committed files      |
| IX. Testing & Validation                       | ✅ Pass | Pre-merge validation workflow is defined              |

**Gate Result (Pre-Research)**: ✅ Pass

### Post-Design Re-Check

| Principle                                      | Status  | Notes                                                  |
| ---------------------------------------------- | ------- | ------------------------------------------------------ |
| I. GitOps & Declarative Infrastructure         | ✅ Pass | Contracts and quickstart keep the workflow declarative |
| II. Infrastructure-as-Code & Reproducibility   | ✅ Pass | Data model and contracts define repeatable patterns    |
| III. Template & Bootstrappability              | ✅ Pass | Quickstart provides deterministic onboarding flow      |
| IV. Modular Architecture                       | ✅ Pass | Module/live relationships are explicit in artifacts    |
| V. Code Quality, Readability & Design Patterns | ✅ Pass | Placement and naming rules are captured                |
| VI. DRY Principles                             | ✅ Pass | Module contract avoids duplicated live definitions     |
| VII. Observability & Failure Transparency      | ✅ Pass | Validation contract includes error signaling           |
| VIII. Security & Least Privilege               | ✅ Pass | State and secret handling constraints preserved        |
| IX. Testing & Validation                       | ✅ Pass | Validation steps documented for contributors           |

**Gate Result (Post-Design)**: ✅ Pass

## Project Structure

### Documentation (this feature)

```text
specs/001-setup-opentofu-cloudflare/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── iac-foundation.openapi.yaml
└── tasks.md
```

### Source Code (repository root)

```text
iac/
├── live/
│   └── cloudflare/
│       └── homelab/
│           ├── backend.tf
│           ├── main.tf
│           ├── providers.tf
│           ├── variables.tf
│           └── outputs.tf
├── modules/
│   └── cloudflare/
│       └── zone-baseline/
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           └── versions.tf
└── README.md
```

**Structure Decision**: Use a category-first IaC layout under `iac/`, with reusable artifacts in
`modules/` and environment intent in `live/`. This supports immediate Cloudflare onboarding and
future categories (`networking`, `kubernetes`) without reshaping existing paths.

## Complexity Tracking

No constitution violations requiring justification.
