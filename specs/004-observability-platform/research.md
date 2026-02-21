# Research: Observability Platform

## Decision 1: Metrics, Alerting & Visualization Stack

**Decision**: Deploy `kube-prometheus-stack` (prometheus-community Helm chart)

**Rationale**: The kube-prometheus-stack is the de-facto standard for Kubernetes cluster
monitoring. It bundles the Prometheus Operator, Prometheus, Alertmanager, Grafana,
node-exporter (node metrics), and kube-state-metrics (Kubernetes object metrics) into a single,
coordinated Helm release. This satisfies FR-001 (auto-discovery via PodMonitor/ServiceMonitor
CRDs), FR-002 (pre-built dashboards provisioned on install), FR-003/FR-004 (Alertmanager with
Slack receiver), FR-008 (automatic scrape target discovery via operator), and FR-011
(self-monitoring).

**OCI Source**: `oci://ghcr.io/home-operations/charts-mirror/kube-prometheus-stack`
This follows the repo's established pattern for community charts (same mirror used for
metrics-server, external-dns, etc.).

**Alternatives considered**:

- Victoria Metrics: lighter weight, but less community tooling and fewer homelab examples
- Standalone Prometheus + Grafana: more control but loses the operator's auto-discovery
  and coordinated upgrades

______________________________________________________________________

## Decision 2: Log Aggregation

**Decision**: Deploy `loki` (grafana Helm chart) in single-binary mode with filesystem backend

**Rationale**: Loki is Grafana Labs' purpose-built log aggregation system and integrates natively
with Grafana (satisfying FR-009 — metric-to-log navigation). Single-binary mode runs all Loki
components in one process — ideal for homelab scale (3–6 nodes, ~50–200 pods). The filesystem
backend stores log chunks on a node-local PVC, consistent with the clarified storage decision
(node-local initially, replicated in future).

**OCI Source**: `oci://ghcr.io/home-operations/charts-mirror/loki`

**Alternatives considered**:

- PLG stack (Promtail + Loki + Grafana): Promtail is simpler but deprecated in favor of Alloy
- Elasticsearch + Kibana: far too resource-heavy for a homelab
- Grafana Cloud (hosted Loki): violates self-hosted requirement

______________________________________________________________________

## Decision 3: Log Collection (Shipper)

**Decision**: Deploy `alloy` (grafana Helm chart) as a DaemonSet

**Rationale**: Grafana Alloy is the official replacement for Promtail and is the actively
maintained log shipper in the Grafana ecosystem. Running as a DaemonSet (one pod per node)
ensures logs are captured from all pods on every node (FR-005). Alloy is configured to tail
pod stdout/stderr via the Kubernetes API and forward to Loki with namespace, pod name, and
container name labels.

**OCI Source**: `oci://ghcr.io/home-operations/charts-mirror/alloy`

**Alternatives considered**:

- Promtail: simpler configuration, but officially deprecated by Grafana; using it would
  introduce technical debt immediately
- Fluent Bit: excellent performance, but requires separate Grafana data source configuration

______________________________________________________________________

## Decision 4: Secret Management

**Decision**: ExternalSecret pulling from 1Password for all app secrets

**Rationale**: The repo already has external-secrets + 1Password ClusterSecretStore configured
and in active use (headlamp uses it). This satisfies Constitution Principle VIII. Two secrets
are required:

1. `grafana-admin-creds` — Grafana admin username + password
2. `alertmanager-slack-webhook` — Slack incoming webhook URL

**Alternatives considered**:

- SOPS-encrypted secrets: valid but the Assumptions section explicitly prefers ExternalSecret
  for app secrets in this cluster

______________________________________________________________________

## Decision 5: Ingress / Gateway

**Decision**: HTTPRoute on `envoy-external` gateway (existing pattern)

**Rationale**: Grafana is the only component that needs external access. Loki and Prometheus
are cluster-internal only (accessed by Grafana as data sources via cluster DNS). The existing
headlamp HTTPRoute pattern (`envoy-external` gateway, `https` section, `*.${SECRET_DOMAIN}`
hostname) is followed exactly.

**Hostname**: `grafana.${SECRET_DOMAIN}` (resolved from cluster-secrets)

______________________________________________________________________

## Decision 6: Scrape Target Discovery

**Decision**: Prometheus Operator CRDs — ServiceMonitor and PodMonitor

**Rationale**: kube-prometheus-stack installs the Prometheus Operator which watches
ServiceMonitor and PodMonitor custom resources. The default configuration scrapes all standard
Kubernetes components automatically. Future apps can opt in to scraping by adding a
ServiceMonitor or PodMonitor in their namespace — no changes needed to Prometheus config
(satisfying FR-008).

**Selector configuration**: `serviceMonitorSelectorNilUsesHelmValues: false` and
`podMonitorSelectorNilUsesHelmValues: false` — instructs the operator to discover monitors
across all namespaces.

______________________________________________________________________

## Decision 7: Chart Versions (initial; Renovate manages ongoing updates)

| Component             | Chart                 | Initial Version |
| --------------------- | --------------------- | --------------- |
| kube-prometheus-stack | kube-prometheus-stack | 70.4.2          |
| Loki                  | loki                  | 6.29.0          |
| Alloy                 | alloy                 | 1.0.3           |

Renovate is already configured in this repo and will automatically open PRs when new chart
versions are published to the OCI mirror.

> ⚠️ **OCI URL verification required (first task)**: The URLs
> `oci://ghcr.io/home-operations/charts-mirror/kube-prometheus-stack`,
> `oci://ghcr.io/home-operations/charts-mirror/loki`, and
> `oci://ghcr.io/home-operations/charts-mirror/alloy` follow the repo's established mirror
> pattern but MUST be verified to exist before writing manifests. Verify with:
> `crane ls ghcr.io/home-operations/charts-mirror/kube-prometheus-stack` (and the same for loki,
> alloy). If a chart is absent from the mirror, fall back to the upstream OCI registry
> (e.g., `oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack`).

______________________________________________________________________

## Resolved Unknowns

| Unknown                    | Resolution                                                             |
| -------------------------- | ---------------------------------------------------------------------- |
| Alert notification channel | Slack via incoming webhook URL (Q1 clarification)                      |
| Storage durability         | Node-local PVC; replicated storage is future goal (Q2 clarification)   |
| Scrape interval            | 30 seconds (Q3 clarification)                                          |
| Metrics retention          | 30 days (Assumptions section)                                          |
| Log retention              | 7 days (Assumptions section)                                           |
| Grafana auth               | Local admin account via ExternalSecret; SSO out of scope (Assumptions) |
