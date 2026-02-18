<!--
  SYNC IMPACT REPORT
  ==================
  Version change: (new) → 1.0.0
  Added sections:
    - Core Principles (all 9 principles)
    - Development Standards
    - Governance
  Modified principles: N/A (initial constitution)
  Removed sections: N/A (initial constitution)
  Templates requiring updates:
    - .specify/templates/plan-template.md ✅ no changes required; Constitution Check section is generic
    - .specify/templates/spec-template.md ✅ no changes required
    - .specify/templates/tasks-template.md ✅ no changes required
  Follow-up TODOs: None
-->

# home-ops Constitution

## Core Principles

### I. GitOps & Declarative Infrastructure

The cluster state MUST be entirely driven by Git. All changes to cluster resources MUST be expressed
as Git commits and reconciled automatically by Argo CD/Flux. Manual `kubectl apply` or out-of-band
mutations are strictly prohibited in production. The repository is the single source of truth;
if it is not in Git, it does not exist in the cluster.

### II. Infrastructure-as-Code & Reproducibility

All infrastructure—nodes, networking, storage, secrets backends, and application configuration—MUST
be expressed as code or declarative manifests committed to this repository. A cluster MUST be
fully reproducible from the repository alone, with no undocumented manual steps. Undocumented
external dependencies are prohibited.

### III. Template & Bootstrappability

This repository MUST serve as a reusable template that allows others to bootstrap their own
homelab Kubernetes cluster. Components MUST be configured via clearly documented variables/values
files. Setup instructions MUST be complete and self-contained so that a new operator can reach a
running cluster by following the README alone, without prior knowledge of this specific environment.

### IV. Modular Architecture

Every feature, component, and application MUST be independently enable/disable-able without
affecting unrelated parts of the cluster. No component MUST assume the presence of another unless
an explicit, documented dependency exists. Helm values, Kustomize overlays, and Argo CD/Flux
ApplicationSets MUST expose toggle points for each major capability.

### V. Code Quality, Readability & Design Patterns

All manifests, Helm values, scripts, and configuration files MUST be readable by a competent
Kubernetes operator without inline explanation. Consistent naming conventions, directory layouts,
and structural patterns MUST be followed throughout. Magic values MUST be replaced with named
variables. Complexity MUST be justified; the simplest solution that satisfies requirements is
preferred.

### VI. DRY Principles

Duplication of configuration, secrets references, image tags, or structural patterns is prohibited.
Shared values MUST be extracted into common Helm values files, Kustomize bases, or configurable
variables. Renovate MUST manage dependency versions centrally; version pins MUST not be duplicated
across manifests.

### VII. Observability & Failure Transparency

Every deployed component MUST emit sufficient signals (logs, metrics, or health endpoints) to
diagnose failures without cluster access beyond read-only tooling. Argo CD/Flux sync status, health
checks, and alerts MUST surface failures visibly. Silent failures—where a component degrades
without any observable signal—are prohibited.

### VIII. Security & Least Privilege

All workloads MUST run with the minimum permissions required. Secrets MUST never be stored in
plaintext in Git; SOPS encryption or external secret references (e.g., 1Password via
External Secrets Operator) are required. Service accounts MUST be scoped to the namespace and
role required. Network policies MUST restrict inter-workload traffic to declared, necessary paths.

### IX. Testing & Validation

All infrastructure changes MUST be validated before merge where tooling permits (e.g., `helm template`, `kustomize build`, manifest linting, CI checks via GitHub Actions). Renovate-driven
updates MUST pass CI before auto-merge. Manual changes that bypass validation gates MUST be
documented with an explicit justification.

## Development Standards

- Changes to cluster state MUST go through a pull request with at least one passing CI check.
- Argo CD/Flux ApplicationSets and Applications MUST use health checks and sync waves where ordering
  matters.
- Helm chart versions and container image tags MUST be managed by Renovate; hardcoded versions
  outside of Renovate-tracked files are prohibited.
- Secrets MUST be encrypted with SOPS before commit; unencrypted secret values in any tracked
  file will be treated as a security incident.
- New components MUST include a README or inline documentation describing purpose, configuration
  toggles, and any external dependencies.

## Governance

This constitution supersedes all informal practices and prior conventions. Any amendment MUST be
proposed via pull request, reviewed against all nine principles, and recorded with a version bump
per the semantic versioning policy below:

- **MAJOR**: Backward-incompatible governance changes, principle removals, or redefinitions that
  require migration of existing cluster state.
- **MINOR**: New principle added, new mandatory section introduced, or materially expanded guidance.
- **PATCH**: Clarifications, wording improvements, typo fixes, or non-semantic refinements.

All pull requests and code reviews MUST verify compliance with this constitution. Violations
require explicit justification recorded in the PR description before merge.

**Version**: 1.0.0 | **Ratified**: 2026-02-18 | **Last Amended**: 2026-02-18
