# Implementation Plan: External Secrets Operator with 1Password

**Branch**: `001-external-secrets-1password` | **Date**: 2026-02-21 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-external-secrets-1password/spec.md`

## Summary

Deploy External Secrets Operator (ESO) and 1Password Connect as a complementary secret management
layer alongside the existing SOPS workflow. New application secrets are stored in a dedicated
1Password vault ("Kubernetes") and pulled into the cluster as Kubernetes Secrets via
`ExternalSecret` resources. The bootstrap credentials for the Connect server are stored as a
SOPS-encrypted file in the repository, consistent with existing secret patterns. ESO is configured
with a Prometheus ServiceMonitor and Grafana dashboard, following the observability convention
already established by cert-manager and flux-operator. The 1Password Connect server runs as a
single replica with a rolling update strategy.

## Technical Context

**Language/Version**: YAML manifests (Kubernetes resources, Helm values)
**Primary Dependencies**:

- ESO Helm chart `2.0.1` — `oci://ghcr.io/external-secrets/charts/external-secrets`
- bjw-s app-template `4.6.2` — `oci://ghcr.io/bjw-s-labs/helm/app-template` (for 1Password Connect)
- 1Password Connect API image `ghcr.io/1password/connect-api:1.8.1`
- 1Password Connect Sync image `ghcr.io/1password/connect-sync:1.8.1`
  **Storage**: emptyDir for 1Password Connect sync cache (ephemeral; cache rebuilds on restart)
  **Testing**: `task lint` (yamlfmt + pre-commit), `task dev:validate` (flux-local renders all HelmReleases and Kustomizations)
  **Target Platform**: Kubernetes cluster (Talos Linux, Flux GitOps via flux-operator)
  **Performance Goals**: Secret sync within 1 hour of a 1Password vault update
  **Constraints**: Single replica Connect server; no new persistent volumes; SOPS files untouched
  **Scale/Scope**: Homelab (~5 existing apps, O(10) new ExternalSecrets initially)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle                        | Status  | Notes                                                                          |
| -------------------------------- | ------- | ------------------------------------------------------------------------------ |
| I. GitOps & Declarative          | ✅ Pass | All resources committed as YAML; Flux reconciles                               |
| II. IaC & Reproducibility        | ✅ Pass | Bootstrap secret SOPS-encrypted in repo; fully git-reproducible                |
| III. Bootstrappability           | ✅ Pass | SOPS credentials in repo; no undocumented manual steps                         |
| IV. Modular Architecture         | ✅ Pass | ESO and 1Password Connect are separate Kustomizations with explicit dependency |
| V. Code Quality                  | ✅ Pass | Follows existing namespace/app directory conventions exactly                   |
| VI. DRY                          | ✅ Pass | Single ClusterSecretStore reused cluster-wide; Renovate manages image tags     |
| VII. Observability               | ✅ Pass | ServiceMonitor + Grafana dashboard enabled on ESO                              |
| VIII. Security & Least Privilege | ✅ Pass | Bootstrap secret SOPS-encrypted; no plaintext in git; Connect token scoped     |
| IX. Testing & Validation         | ✅ Pass | `task lint` + `task dev:validate` validates before merge                       |

**Gate result**: ✅ All principles satisfied. No violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/001-external-secrets-1password/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── externalsecret-template.yaml   # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks — not created here)
```

### Source Code (repository root)

```text
kubernetes/apps/external-secrets/
├── kustomization.yaml          # namespace-level Kustomize root (new namespace entry point)
├── namespace.yaml              # external-secrets Namespace
├── external-secrets/           # ESO app
│   ├── ks.yaml                 # Flux Kustomization for ESO
│   └── app/
│       ├── kustomization.yaml
│       ├── ocirepository.yaml  # ghcr.io/external-secrets/charts/external-secrets:2.0.1
│       └── helmrelease.yaml    # ESO with serviceMonitor + grafanaDashboard enabled
└── onepassword/                # 1Password Connect app
    ├── ks.yaml                 # Flux Kustomization (dependsOn: external-secrets)
    └── app/
        ├── kustomization.yaml
        ├── ocirepository.yaml  # ghcr.io/bjw-s-labs/helm/app-template:4.6.2
        ├── helmrelease.yaml    # 1Password Connect (api + sync containers, single replica)
        ├── clustersecretstore.yaml   # ClusterSecretStore "onepassword"
        └── secret.sops.yaml    # SOPS-encrypted bootstrap secret (onepassword-secret)
```

**Structure Decision**: New `external-secrets` namespace added under `kubernetes/apps/` following
the identical directory pattern used by `cert-manager`, `network`, and all other namespaces. The
namespace-level `kustomization.yaml` is the Kustomize entry point discovered by Flux when it
renders `./kubernetes/apps`. Two sub-apps (ESO and 1Password Connect) each have their own
`ks.yaml` (Flux Kustomization) and `app/` directory, enabling independent reconciliation and
clear dependency ordering.

## Complexity Tracking

No constitution violations requiring justification.
