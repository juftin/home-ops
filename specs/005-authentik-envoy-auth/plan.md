# Implementation Plan: Authentik Cluster Authentication

**Branch**: `005-authentik-envoy-auth` | **Date**: 2026-03-03 | **Spec**: [/Users/juftin/git/home-ops/specs/005-authentik-envoy-auth/spec.md](/Users/juftin/git/home-ops/specs/005-authentik-envoy-auth/spec.md)
**Input**: Feature specification from `/specs/005-authentik-envoy-auth/spec.md`

## Summary

Stand up Authentik in-cluster and integrate it as a gateway authentication path for a phased subset of protected routes while preserving existing Google-proxy authentication for non-selected routes. The design prioritizes deny-by-default behavior on unassigned routes, explicit route-to-auth-path assignment, and 30-day queryable authentication outcome records.

## Technical Context

**Language/Version**: YAML manifests (Kubernetes + HelmRelease values), Taskfile workflows
**Primary Dependencies**: Flux reconciliation, Envoy Gateway, Authentik Helm deployment, existing Google-proxy auth path, Cloudflare Tunnel routing
**Storage**: Kubernetes resources in Git; secret material via ExternalSecret references from 1Password with SOPS-encrypted fallback only when required; auth event records retained in platform logs/metrics pipeline
**Testing**: `task lint`, `task dev:validate`, branch validation workflow (`task dev:start`, `task dev:sync`, `task dev:stop`)
**Target Platform**: Talos-backed Kubernetes cluster managed by Flux
**Project Type**: GitOps infrastructure configuration
**Performance Goals**: Match spec outcomes (>=95% successful Authentik sign-ins complete and return to destination in \<30s)
**Constraints**: Phased migration subset required; unassigned protected routes must deny; 30-day queryable auth outcome records; no plaintext secrets; no direct kubectl apply testing
**Scale/Scope**: Route-level auth assignment across existing protected apps, with initial migration limited to a defined subset

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle                                | Status | Plan Alignment                                                                              |
| ---------------------------------------- | ------ | ------------------------------------------------------------------------------------------- |
| GitOps & Declarative Infrastructure      | PASS   | All changes are manifest/values updates in `kubernetes/`; Flux remains source of truth.     |
| Infrastructure-as-Code & Reproducibility | PASS   | No manual cluster-only configuration required; branch workflow validates declarative state. |
| Template & Bootstrappability             | PASS   | Feature docs and quickstart include repeatable flow for operators.                          |
| Modular Architecture                     | PASS   | Route-level assignment allows independent enablement of Authentik per app.                  |
| Code Quality & Simplicity                | PASS   | Reuse existing oauth/envoy/cloudflare patterns with minimal new objects.                    |
| DRY Principles                           | PASS   | Shared auth-path conventions and centralized manifests avoid duplicated logic.              |
| Observability & Failure Transparency     | PASS   | Include explicit auth outcome signals and failure responses for route/auth-path visibility. |
| Security & Least Privilege               | PASS   | Deny-by-default on unassigned routes; secret handling remains SOPS/ExternalSecret only.     |
| Testing & Validation                     | PASS   | Validate via `task lint` and `task dev:validate` before merge.                              |

## Project Structure

### Documentation (this feature)

```text
specs/005-authentik-envoy-auth/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── auth-routing.openapi.yaml
└── tasks.md               # generated later by /speckit.tasks
```

### Source Code (repository root)

```text
kubernetes/apps/network/envoy-gateway/
├── app/
└── ks.yaml

kubernetes/apps/security/authentik/
├── app/
└── ks.yaml

kubernetes/apps/network/cloudflare-tunnel/
├── app/
└── ks.yaml

kubernetes/apps/default/oauth-pages/
├── app/
└── ks.yaml

kubernetes/apps/<namespace>/<app>/
└── app/                   # app route assignments and auth policy references
```

**Structure Decision**: Use existing GitOps layout under `kubernetes/apps/**`; add a new `security/authentik` app and update auth-relevant app/network manifests; keep all feature planning artifacts in `specs/005-authentik-envoy-auth/`.

## Phase 0: Research

- Document decision records for Authentik deployment model, auth-path strategy, route assignment model, failure handling, and observability targets.
- Resolve technical unknowns around callback routing, phased migration controls, and record retention feasibility.
- Output: `research.md`.

## Phase 1: Design & Contracts

- Define entities, validation constraints, and transitions for Authentik deployment, protected routes, and auth outcomes.
- Generate contract for route auth assignment/evaluation and outcome query semantics.
- Create operator quickstart for phased rollout and verification.
- Refresh agent context with plan-specific tech terms.
- Outputs: `data-model.md`, `contracts/auth-routing.openapi.yaml`, `quickstart.md`.

## Phase 2: Planning Readiness

- Re-check constitution gate after design artifacts.
- Confirm no unresolved clarifications remain from spec.
- Prepare for `/speckit.tasks` generation.

## Constitution Check (Post-Design)

| Principle        | Status | Notes                                                                                                                                        |
| ---------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| All 9 principles | PASS   | Research/design artifacts preserve GitOps-only flow, security boundaries, observability requirements, and pre-merge validation expectations. |

## Complexity Tracking

No constitution violations identified.
