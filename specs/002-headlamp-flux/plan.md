# Implementation Plan: Headlamp + Flux Plugin

**Branch**: `002-headlamp-flux` | **Date**: 2026-02-21 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-headlamp-flux/spec.md`

## Summary

Extend the partial Headlamp deployment on the `headlamp-app` branch with the four missing
resources: `ServiceAccount`, `ClusterRoleBinding`, `ExternalSecret` (syncing
`headlamp-admin-token` from 1Password), and a standalone `HTTPRoute` exposing Headlamp at
`headlamp.${SECRET_DOMAIN}` via the `envoy-external` Gateway. The existing `ks.yaml` also
requires a `postBuild.substituteFrom` addition for variable substitution to work.

## Technical Context

**Language/Version**: YAML / Kubernetes manifests (no application code)
**Primary Dependencies**: Flux v2, External Secrets Operator v1, Headlamp Helm chart v0.33.0, Gateway API (HTTPRoute), 1Password Connect
**Storage**: N/A
**Testing**: `task lint` (yamlfmt auto-fix), `task dev:validate` (flux-local offline render)
**Target Platform**: Talos Linux / Kubernetes homelab cluster (single-node or multi-node)
**Project Type**: GitOps manifest additions — no src/ tree
**Performance Goals**: Headlamp UI loads within 10 seconds of navigation (SC-001)
**Constraints**: GitOps-only (no `kubectl apply`); all secrets via SOPS or ExternalSecret; `envoy-external` Gateway for HTTPS ingress
**Scale/Scope**: Single homelab cluster, single operator user

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle                          | Status                 | Notes                                                                                             |
| ---------------------------------- | ---------------------- | ------------------------------------------------------------------------------------------------- |
| I — GitOps & Declarative           | ✅ Pass                | All resources reconciled by Flux; no out-of-band applies                                          |
| II — IaC & Reproducibility         | ✅ Pass                | All manifests committed; no undocumented manual steps                                             |
| III — Template & Bootstrappability | ✅ Pass                | Follows existing patterns; no new external dependencies                                           |
| IV — Modular Architecture          | ✅ Pass                | Isolated in `observability/headlamp/`; independently disable-able via ks.yaml                     |
| V — Code Quality                   | ✅ Pass                | Consistent naming conventions matching existing apps                                              |
| VI — DRY                           | ✅ Pass                | Reuses `onepassword` ClusterSecretStore, `envoy-external` Gateway, `cluster-secrets` substitution |
| VII — Observability                | ✅ Pass                | Headlamp + Flux plugin IS the observability layer                                                 |
| VIII — Security & Least Privilege  | ⚠️ Justified Exception | `cluster-admin` violates least privilege — see Complexity Tracking                                |
| IX — Testing & Validation          | ✅ Pass                | `task lint` + `task dev:validate` validates all manifests offline                                 |

## Project Structure

### Documentation (this feature)

```text
specs/002-headlamp-flux/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
kubernetes/apps/observability/
├── kustomization.yaml                        # EXISTING — already references headlamp/ks.yaml
└── headlamp/
    ├── ks.yaml                               # UPDATE — add postBuild.substituteFrom
    └── app/
        ├── kustomization.yaml                # UPDATE — add all new resource files
        ├── helmrelease.yaml                  # EXISTING — no changes needed
        ├── serviceaccount.yaml               # NEW
        ├── clusterrolebinding.yaml           # NEW
        ├── externalsecret.yaml               # NEW
        └── httproute.yaml                    # NEW
```

**Structure Decision**: Manifest-only GitOps additions. No src/ tree. All new files follow
the existing pattern in `kubernetes/apps/observability/headlamp/app/`. Reference app:
`kubernetes/apps/default/echo/` and `kubernetes/apps/flux-system/flux-instance/`.

## Complexity Tracking

| Violation                                                                    | Why Needed                                                                                             | Simpler Alternative Rejected Because                                                                                                                                      |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cluster-admin` ClusterRoleBinding (violates Principle VIII least-privilege) | Homelab dashboard must display all resources including Secrets, CustomResources, and system namespaces | The built-in `view` ClusterRole hides Secrets entirely; a custom read-all ClusterRole would need to enumerate every API group and is fragile against new CRDs being added |
