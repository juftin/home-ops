# Implementation Plan: Headlamp Token Sync Reliability

**Branch**: `001-fix-headlamp-token-sync` | **Date**: 2026-03-12 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-fix-headlamp-token-sync/spec.md`

## Summary

Stabilize Headlamp authentication by making token authority explicit, reducing drift between
1Password-originated secrets and runtime auth behavior, and adding operator-visible sync health.
The plan introduces deterministic source precedence, bounded propagation expectations, auditable
eventing, and a contract for sync-status visibility and incident handling.

## Technical Context

**Language/Version**: YAML (Kubernetes manifests), Bash task workflow, Markdown specs
**Primary Dependencies**: Flux, External Secrets Operator + 1Password Connect, Envoy Gateway OIDC
SecurityPolicy, Headlamp HelmRelease
**Storage**: Kubernetes Secret resources sourced from 1Password via ExternalSecret
**Testing**: `task lint`, `task dev:validate`, targeted on-cluster checks from OIDC runbooks
**Target Platform**: Talos-based Kubernetes homelab (bare metal), `observability` + `network`
namespaces
**Project Type**: GitOps infrastructure configuration
**Performance Goals**: New logins reflect token rotations within 5 minutes; token drift surfaced
to operators within 1 minute
**Constraints**: No plaintext secrets in Git; fail-closed auth behavior; no manual cluster drift
from `kubectl apply`
**Scale/Scope**: Single Headlamp app path now, pattern reusable for additional OAuth-protected apps

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Design Gate

| Principle                                 | Status  | Notes                                                        |
| ----------------------------------------- | ------- | ------------------------------------------------------------ |
| I. GitOps & Declarative Infrastructure    | ✅ Pass | All changes are manifest/spec artifacts in Git.              |
| II. IaC & Reproducibility                 | ✅ Pass | Secrets and policy behavior are declared and reviewable.     |
| III. Template & Bootstrappability         | ✅ Pass | Uses existing app and spec conventions.                      |
| IV. Modular Architecture                  | ✅ Pass | Scope limited to Headlamp + shared auth primitives.          |
| V. Code Quality & Readability             | ✅ Pass | Follows existing `kubernetes/apps/...` layout and naming.    |
| VI. DRY Principles                        | ✅ Pass | Reuses existing OAuth policy and ExternalSecret patterns.    |
| VII. Observability & Failure Transparency | ✅ Pass | Adds explicit sync-health and incident visibility artifacts. |
| VIII. Security & Least Privilege          | ✅ Pass | Secret material remains in SOPS/ESO flow; fail-closed auth.  |
| IX. Testing & Validation                  | ✅ Pass | Validation flow is `task lint` then `task dev:validate`.     |

### Post-Design Gate (after Phase 1)

All principles remain **✅ Pass** after introducing `research.md`, `data-model.md`,
`contracts/token-sync.openapi.yaml`, and `quickstart.md`. No violations require justification.

## Project Structure

### Documentation (this feature)

```text
specs/001-fix-headlamp-token-sync/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── token-sync.openapi.yaml
│   └── README.md
└── tasks.md
```

### Source Code (repository root)

```text
kubernetes/apps/observability/headlamp/
├── ks.yaml
└── app/
    ├── externalsecret.yaml
    ├── helmrelease.yaml
    ├── httproute.yaml
    ├── serviceaccount.yaml
    └── clusterrolebinding.yaml

kubernetes/apps/network/envoy-gateway/app/
├── envoy.yaml
├── oauth-policy.sops.yaml
└── oauth-policy-internal.sops.yaml

kubernetes/apps/external-secrets/onepassword/app/
└── clustersecretstore.yaml
```

**Structure Decision**: This is an infrastructure-only feature using existing app directories in
`observability`, `network`, and `external-secrets`; no new top-level code modules are needed.

## Implementation Phases

### Phase 0 — Research

Produce `research.md` with decisions for source-of-truth precedence, token drift detection,
rotation propagation strategy, and validation/rollback approach.

### Phase 1 — Design & Contracts

Produce `data-model.md` for token/sync entities and transitions, create
`contracts/token-sync.openapi.yaml` for operator-facing status and incident actions, and provide
`quickstart.md` for implementation and verification flow.

### Phase 2 — Task Planning

Generate `tasks.md` via `/speckit.tasks` after this plan is reviewed.

## Handoff Notes

- Runtime authority for Headlamp token decisions is the materialized Kubernetes Secret
  `headlamp-admin-token`.
- Envoy OAuth remains the gateway auth control-plane; this feature adds drift visibility and
  deterministic source precedence rather than replacing OAuth behavior.
- Operator triage entry points:
  - `docs/OIDC-TROUBLESHOOTING.md` section "Headlamp token appears stale after secret rotation"
  - `docs/POST-MERGE-VERIFICATION.md` section "Token Sync Follow-up (Headlamp)"

## Measurable Outcomes Mapping

- **SC-001**: Rotation reflected within 5 minutes, enforced by 1-minute ExternalSecret refresh and
  reloader-bound rollout annotations.
- **SC-002**: Deterministic conflict handling via explicit precedence metadata and reason codes.
- **SC-003**: Operator visibility through `/token-sync/status`, `/token-sync/sources`, and
  `/token-sync/incidents` endpoints.
- **SC-004**: Incident lifecycle (`open`, `mitigating`, `resolved`) represented in persisted state
  templates and quickstart verification flow.
