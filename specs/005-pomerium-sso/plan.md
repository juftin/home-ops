# Implementation Plan: Replace Envoy OAuth with Pomerium SSO

**Branch**: `005-pomerium-sso` | **Date**: 2026-11-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/005-pomerium-sso/spec.md`

## Summary

Replace the hand-rolled Envoy Gateway Google OIDC setup (`envoy-oauth-admin`, `envoy-oauth-users`, `envoy-oauth-internal`, SOPS `SecurityPolicy` files, header-limit `EnvoyPatchPolicy`, 403 `BackendTrafficPolicy`, and `apps/oauth-pages`) with **Pomerium Ingress Controller (`v0.34.1`)** deployed via Kustomize under `kubernetes/workloads/network/pomerium/`. Retain the existing `Admins` and `Users` access tiers using YAML anchors inside a single SOPS-encrypted `List` of `Ingress` resources (`ingresses.sops.yaml`), while keeping `envoy-external` and `envoy-internal` unchanged for public and LAN-only workloads.

## Technical Context

**Language/Version**: YAML/Kubernetes manifests; Pomerium Ingress Controller `v0.34.1`; Kustomize `v5.7+`; Helm `v4` / Helmfile; SOPS + age; Bash
**Primary Dependencies**: `github.com/pomerium/ingress-controller/config/default?ref=v0.34.1` (`Pomerium` CRD `ingress.pomerium.io/v1`, `Ingress` `networking.k8s.io/v1`), `cert-manager` (`network/${SECRET_DOMAIN/./-}-production-tls`), Cilium `CiliumNetworkPolicy`, Cloudflare Tunnel (`cloudflared`), ArgoCD
**Storage**: Persistent `node-local` PVC (`1Gi`) mounted at `/var/lib/pomerium` for Pomerium's built-in `file` databroker storage
**Testing**: `task lint` (`pre-commit`, `yamlfmt`, `mdformat`, `shellcheck`, `actionlint`), `task dev:validate:ci` (offline Kustomize + Helm + `kubeconform -strict`), `task dev:validate` (full SOPS decryption)
**Target Platform**: Kubernetes on Talos Linux (single-node bare metal homelab); Pomerium control plane in `pomerium` namespace (managed via `kubernetes/workloads/network/pomerium/`)
**Performance Goals**: Interactive SSO login/redirect (\<2s), WebSocket support for agent UIs/Grafana/ArgoCD, zero overhead for `envoy-external`/`envoy-internal` routes
**Constraints**: Zero plaintext emails or OAuth secrets in Git; no decryption of existing `.sops.yaml` during development without `age.key`; Renovate-tracked container image versions (no `:main` tag); all existing `task lint` and `task dev:validate:ci` checks must pass
**Scale/Scope**: 1 Pomerium instance (`replicas: 1`, `Recreate`), 7 protected apps (`agentsview`, `paseo`, `herdr`, `hermes-agent`, `openclaw`, `argocd`, `grafana`), 2 access groups (`Admins`, `Users`)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle                                      | Status | Notes                                                                                                                               |
| ---------------------------------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| I. GitOps & Declarative Infrastructure         | Pass   | All Pomerium, Ingress, Tunnel, and NetworkPolicy manifests are committed to Git for ArgoCD reconciliation.                          |
| II. Infrastructure-as-Code & Reproducibility   | Pass   | Pinned `v0.34.1` Kustomize base + declarative SOPS secrets + automated migration script.                                            |
| III. Template & Bootstrappability              | Pass   | Uses `${SECRET_DOMAIN}` placeholders; updates `templates/` alongside live `kubernetes/` and `bootstrap/`.                           |
| IV. Modular Architecture                       | Pass   | `envoy-external` and `envoy-internal` remain untouched; `pomerium` is isolated in `kubernetes/workloads/network/pomerium/`.         |
| V. Code Quality, Readability & Design Patterns | Pass   | Follows existing `kubernetes/workloads/` layout, `PodMonitor` pattern, and `yamlfmt`/`mdformat` standards.                          |
| VI. DRY Principles                             | Pass   | `Admins` and `Users` PPL policies use YAML anchors in one `ingresses.sops.yaml` file; image tag pinned with Renovate comment.       |
| VII. Observability & Failure Transparency      | Pass   | Adds `PodMonitor` scraping `pomerium-metrics:9090` and preserves readiness/liveness probes.                                         |
| VIII. Security & Least Privilege               | Pass   | SOPS encrypts `ingress.pomerium.io/policy` and `google-idp` secret; Cilium network policies scope ingress to `pomerium-proxy` pods. |
| IX. Testing & Validation                       | Pass   | Validated via `task lint`, `task dev:validate:ci`, and `task dev:validate:test`.                                                    |

Post-Phase 1 re-check: All 9 principles pass with zero violations.

## Project Structure

### Documentation (this feature)

```text
specs/005-pomerium-sso/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── pomerium-crd.md
│   └── ingress-routes.md
└── tasks.md
```

### Source Code (repository root)

```text
.sops.yaml                                                 # Add encrypted_regex rule for pomerium ingresses.sops.yaml
scripts/migrate-oauth-to-pomerium.sh                       # Local operator script to migrate SOPS secrets/emails
kubernetes/argocd/
├── applicationset.yaml                                    # Remove SecurityPolicy ignoreDifferences
└── appproject.yaml                                        # Ignore pomerium/bootstrap Secret in orphanedResources
kubernetes/workloads/network/pomerium/                     # NEW Pomerium Ingress Controller workload
├── kustomization.yaml
├── pomerium.yaml                                          # Pomerium global CRD
├── pvc.yaml                                               # 1Gi node-local PVC for databroker file storage
├── podmonitor.yaml                                        # Prometheus PodMonitor for pomerium-metrics
├── google-idp-secret.sops.yaml                            # SOPS Google OAuth client_id + client_secret
└── ingresses.sops.yaml                                    # SOPS List of 7 protected Ingresses with YAML anchors
kubernetes/workloads/network/envoy-gateway/                # Remove OAuth Gateways, SecurityPolicies, EnvoyPatchPolicies
kubernetes/workloads/network/cloudflare-tunnel/values.yaml # Route protected hosts + oauth.* to pomerium-proxy
kubernetes/workloads/apps/oauth-pages/                     # REMOVE obsolete static OAuth pages app
kubernetes/workloads/apps/{agentsview,herdr,hermes-agent,openclaw,paseo}/
├── kustomization.yaml                                     # Remove HTTPRoute apiVersion capability
├── values.yaml                                            # Remove envoy-oauth-admin route blocks
└── networkpolicy.yaml                                     # Allow ingress from pomerium-proxy pods
kubernetes/workloads/observability/kube-prometheus-stack/
├── kustomization.yaml                                     # Remove dnsendpoint.yaml
├── dnsendpoint.yaml                                       # REMOVE obsolete grafana -> oauth CNAME
└── values.yaml                                            # Disable grafana.route.main
bootstrap/helmfile.d/templates/values.yaml.gotmpl          # Disable ArgoCD server.httproute (keep argocd-webhook)
templates/config/...                                       # Sync cluster-template envoy-gateway & bootstrap templates
README.md & docs/                                          # Update architecture, access, OAuth, playbook, & setup docs
```

**Structure Decision**: Place Pomerium under `kubernetes/workloads/network/pomerium/` (wave 2) while keeping upstream's `pomerium` namespace so `config/default?ref=v0.34.1` applies cleanly and `ingresses.sops.yaml` can target all 7 app namespaces without Kustomize top-level namespace overrides.
