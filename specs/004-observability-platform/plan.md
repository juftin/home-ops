# Implementation Plan: Observability Platform

**Branch**: `004-observability-platform` | **Date**: 2026-02-21 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/004-observability-platform/spec.md`

## Summary

Deploy a full observability platform to the `observability` namespace using three independent
HelmReleases: **kube-prometheus-stack** (metrics collection, Alertmanager, Grafana, pre-built
dashboards), **Loki** (log aggregation with node-local persistence), and **Alloy** (log shipper
DaemonSet). Slack alerting is configured via a webhook URL stored in 1Password. Grafana is exposed
over HTTPS via the existing Cilium Gateway API. Secrets are injected through ExternalSecret.

## Technical Context

**Language/Version**: YAML manifests; Helm chart values (no compiled code)
**Primary Dependencies**:

- `kube-prometheus-stack` (prometheus-community) — Prometheus Operator, Prometheus, Alertmanager,
  Grafana, node-exporter, kube-state-metrics
- `loki` (grafana) — log storage and query API, single-binary mode, filesystem backend
- `alloy` (grafana) — telemetry collector DaemonSet (log shipper to Loki)

**Storage**: Node-local PersistentVolumeClaims (default storage class); replicated storage is a
future goal. Prometheus: ~30 GB / 30-day retention. Loki: ~10 GB / 7-day retention.

**Testing**: `task lint` (yamlfmt + pre-commit) and `task dev:validate` (flux-local offline render)

**Target Platform**: Talos Linux bare-metal Kubernetes cluster; `observability` namespace (exists)

**Project Type**: GitOps infrastructure (Flux Kustomizations + HelmReleases)

**Performance Goals**:

- Metrics scrape interval: 30 seconds
- Alert detection to Slack notification: ≤3 minutes
- Log query response in UI: ≤30 seconds for a targeted pod search

**Constraints**:

- Node-local storage only (initial deployment); no distributed storage
- Secrets sourced exclusively from 1Password via ExternalSecret (never SOPS for app secrets)
- All resources reconciled by Flux; no `kubectl apply` in production

**Scale/Scope**: Homelab — estimated 3–6 nodes, ~50–200 pods, ~30-day metrics retention,
7-day log retention

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle                                 | Status  | Notes                                                              |
| ----------------------------------------- | ------- | ------------------------------------------------------------------ |
| I. GitOps & Declarative Infrastructure    | ✅ Pass | All resources committed as manifests; no manual kubectl            |
| II. IaC & Reproducibility                 | ✅ Pass | OCI chart tags pinned; values committed; Renovate manages versions |
| III. Template & Bootstrappability         | ✅ Pass | quickstart.md documents all variables; no undocumented steps       |
| IV. Modular Architecture                  | ✅ Pass | Three independent HelmReleases; each disable-able independently    |
| V. Code Quality & Design Patterns         | ✅ Pass | Follows existing headlamp/echo patterns exactly                    |
| VI. DRY Principles                        | ✅ Pass | Shared labels via commonMetadata; versions in one place per chart  |
| VII. Observability & Failure Transparency | ✅ Pass | This feature IS the observability layer; FR-011 self-monitoring    |
| VIII. Security & Least Privilege          | ✅ Pass | ExternalSecret for all secrets; no plaintext in Git                |
| IX. Testing & Validation                  | ✅ Pass | `task dev:validate` runs flux-local before merge                   |

**No violations.** Proceed to Phase 0.

## Project Structure

### Documentation (this feature)

```text
specs/004-observability-platform/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── servicemonitor-selector.md
│   ├── alertrule-schema.md
│   └── loki-label-schema.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
kubernetes/apps/observability/
├── kustomization.yaml                  # MODIFY: add 3 new ks.yaml entries
├── namespace.yaml                      # existing — no change
├── headlamp/                           # existing — no change
├── kube-prometheus-stack/
│   ├── ks.yaml                         # Flux Kustomization
│   └── app/
│       ├── kustomization.yaml          # lists all resources
│       ├── ocirepository.yaml          # chart source pin
│       ├── helmrelease.yaml            # chart values (Prometheus, Alertmanager, Grafana)
│       └── externalsecret.yaml         # grafana-admin-creds + alertmanager-slack-webhook
├── loki/
│   ├── ks.yaml
│   └── app/
│       ├── kustomization.yaml
│       ├── ocirepository.yaml
│       └── helmrelease.yaml            # single-binary mode, filesystem backend, PVC
└── alloy/
    ├── ks.yaml
    └── app/
        ├── kustomization.yaml
        ├── ocirepository.yaml
        └── helmrelease.yaml            # DaemonSet; ships pod logs to Loki
```

**Structure Decision**: Three separate app directories under `observability/` following the
existing headlamp pattern exactly. kube-prometheus-stack owns Grafana and Alertmanager to avoid
split configuration. Loki and Alloy are independent so they can be upgraded separately.

## Complexity Tracking

No constitution violations requiring justification.
