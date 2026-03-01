# Implementation Plan: Envoy Authentik Authentication Migration

**Branch**: `005-migrate-authentik-auth` | **Date**: 2026-03-01 | **Spec**: [/specs/005-migrate-authentik-auth/spec.md](/specs/005-migrate-authentik-auth/spec.md)
**Input**: Feature specification from `/specs/005-migrate-authentik-auth/spec.md`

## Summary

Migrate protected-route authentication from direct Google OAuth in Envoy Gateway to centralized Authentik-based external authorization while preserving a cluster-wide legacy fallback mode. The implementation keeps route intent stable, enforces fail-closed decisions, and preserves future Terraform ownership without changing expected authentication behavior.

## Technical Context

**Language/Version**: YAML manifests (Kubernetes Gateway API, Envoy Gateway CRDs), Taskfile automation
**Primary Dependencies**: FluxCD reconciliation, Envoy Gateway SecurityPolicy/extension points, Authentik as centralized IdP, SOPS/age, Cilium networking
**Storage**: Kubernetes resources in Git (SOPS-encrypted secrets); no new persistent data store
**Testing**: `task lint`, `task dev:validate`, branch validation via `task dev:start`/`task dev:stop`, post-change gateway checks
**Target Platform**: Talos Linux Kubernetes cluster managed by FluxCD
**Project Type**: GitOps infrastructure repository (declarative manifests)
**Performance Goals**: No user-visible regression in protected-route auth flow during mode transition; deny/allow decisions remain immediate at gateway interaction level
**Constraints**: Cluster-wide auth mode switch only; fail closed when decision unavailable; plaintext secrets prohibited; compatibility with future Terraform ownership model
**Scale/Scope**: All currently protected routes attached to OAuth gateway paths; single-cluster homelab scope with operator-managed rollout

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. GitOps & Declarative Infrastructure**: PASS — all changes are declarative under `kubernetes/` and reconciled by Flux.
- **II. Infrastructure-as-Code & Reproducibility**: PASS — no manual runtime-only configuration introduced.
- **IV. Modular Architecture**: PASS — auth mode is explicit and reversible without changing protected-route intent.
- **VII. Observability & Failure Transparency**: PASS — auth decisions require observable outcomes including denial reason.
- **VIII. Security & Least Privilege**: PASS — fail-closed behavior and encrypted secret handling preserved.
- **IX. Testing & Validation**: PASS — plan requires repository validation flow before merge.

No gate violations require exceptions.

## Project Structure

### Documentation (this feature)

```text
specs/005-migrate-authentik-auth/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── auth-mode-management.openapi.yaml
└── tasks.md
```

### Source Code (repository root)

```text
kubernetes/
├── apps/
│   ├── network/
│   │   ├── envoy-gateway/app/          # Gateway, SecurityPolicy, extAuth integration points
│   │   └── cloudflare-tunnel/app/      # Explicit OAuth host ingress ordering
│   └── default/
│       └── oauth-pages/app/            # denied/logged-out utility routing behavior
└── components/
    └── sops/                           # encrypted secret handling component

docs/
├── GATEWAY-ONBOARDING-CHECKLIST.md
├── SECURITYPOLICY-CHANGE-PLAYBOOK.md
└── POST-MERGE-VERIFICATION.md
```

**Structure Decision**: Keep changes constrained to existing gateway, oauth-pages, and tunnel manifests plus spec artifacts for design traceability.

## Phase 0: Research Output

See `research.md` for resolved decisions on mode-switch scope, fail behavior, observability minimum fields, validation gates, and rollback strategy.

## Phase 1: Design & Contracts Output

- Data model documented in `data-model.md`
- Interface contracts documented under `contracts/`
- Operator validation runbook documented in `quickstart.md`
- Agent context refreshed via `.specify/scripts/bash/update-agent-context.sh copilot`

## Post-Design Constitution Check

- **GitOps compliance**: PASS
- **Security & encryption handling**: PASS
- **Observability requirement coverage**: PASS
- **Validation workflow coverage**: PASS

No new constitution violations introduced by Phase 1 outputs.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No constitution violations; complexity tracking not required.
