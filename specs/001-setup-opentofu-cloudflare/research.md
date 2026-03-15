# Research: OpenTofu Cloudflare IaC Foundation

## Decision 1: Tool bootstrap uses existing mise + aqua workflow

- **Decision**: Install OpenTofu through `.mise.toml` using the same aqua-backed pattern as other CLI tooling.
- **Rationale**: This repository already standardizes tool pinning and setup via `mise install`, so extending that flow preserves deterministic onboarding and avoids parallel tool installers.
- **Alternatives considered**:
  - Direct Homebrew/manual OpenTofu install: rejected due to version drift risk.
  - Wrapper scripts downloading binaries ad hoc: rejected due to reproducibility and maintenance overhead.

## Decision 2: Keep a strict `iac/live` and `iac/modules` split

- **Decision**: Use `iac/modules/cloudflare/...` for reusable definitions and `iac/live/cloudflare/homelab/...` for environment intent.
- **Rationale**: The split enforces modularity, supports DRY composition, and aligns with common OpenTofu/Terraform patterns for scaling categories and environments.
- **Alternatives considered**:
  - Flat `iac/cloudflare/*.tf`: rejected because reusable and environment-specific concerns get mixed.
  - Environment-first root structure for this first slice: rejected to preserve clear category onboarding while scope is Cloudflare-only.

## Decision 3: State management defaults to remote backend and excludes local state artifacts from Git

- **Decision**: Design live stacks around remote backend configuration and explicitly disallow committed local state artifacts.
- **Rationale**: Remote state supports team safety and reproducibility while meeting repository security principles around sensitive data handling.
- **Alternatives considered**:
  - Commit local state for bootstrap simplicity: rejected due to security and merge-conflict risks.
  - Defer backend guidance entirely: rejected because it leaves critical operational behavior ambiguous.

## Decision 4: Baseline validation workflow includes format + validate steps for IaC

- **Decision**: Validate IaC with `tofu fmt -check -recursive` and `tofu validate` in addition to repository-wide `task lint`.
- **Rationale**: This gives fast, local failure feedback on IaC structure correctness while staying compatible with existing validation practices.
- **Alternatives considered**:
  - Rely only on `task lint`: rejected because it does not validate HCL semantics.
  - Full plan/apply in planning scope: rejected; out of scope for this foundational structure phase.

## Decision 5: Standard module interface files and explicit live stack module usage

- **Decision**: Define module contracts around `main.tf`, `variables.tf`, `outputs.tf` (and `versions.tf` where needed), with live stacks consuming modules rather than duplicating resources.
- **Rationale**: This is the most recognizable and maintainable module interface pattern for contributors and future category expansion.
- **Alternatives considered**:
  - Monolithic live-only stacks: rejected due to duplication and poor reuse.
  - Highly nested module hierarchy for initial Cloudflare setup: rejected as premature complexity.
