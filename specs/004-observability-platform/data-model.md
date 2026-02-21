# Data Model: Observability Platform

This document maps the spec's Key Entities to concrete Kubernetes resource types, Helm chart
configuration structures, and storage layouts used in this deployment.

______________________________________________________________________

## Entity: Metric

**Spec definition**: A time-series data point with a name, labels (key-value pairs), value, and
timestamp. Collected from scrape targets at a 30-second interval.

**Kubernetes resource**: Managed by the Prometheus Operator. Metrics are collected from endpoints
discovered via `ServiceMonitor` and `PodMonitor` custom resources.

**Storage**:

- Location: Prometheus TSDB on a node-local PersistentVolumeClaim
- PVC size: ~30 GB
- Retention: 30 days (`--storage.tsdb.retention.time=30d`)
- Format: Prometheus TSDB (on-disk block format)

**Key labels** (applied to all scraped metrics):

- `namespace` — Kubernetes namespace of the source pod/service
- `pod` — pod name
- `container` — container name
- `node` — node hostname
- `job` — scrape job name (typically chart name or app label)

______________________________________________________________________

## Entity: Scrape Target

**Spec definition**: A running workload endpoint that exposes metrics. Discovered automatically.

**Kubernetes resources**:

### ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
spec:
  selector:
    matchLabels:
      <app-label>: <value>
  endpoints:
    - port: metrics
      interval: 30s       # matches global scrape interval
      path: /metrics
  namespaceSelector:
    any: true             # cross-namespace discovery enabled
```

### PodMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
spec:
  selector:
    matchLabels:
      <app-label>: <value>
  podMetricsEndpoints:
    - port: metrics
      interval: 30s
  namespaceSelector:
    any: true
```

**Discovery scope**: Prometheus Operator is configured with
`serviceMonitorSelectorNilUsesHelmValues: false` — monitors across all namespaces are discovered
automatically without requiring label matches on the Prometheus resource.

**State transitions**: `UP` (endpoint reachable) → `DOWN` (endpoint unreachable, fires alert)

______________________________________________________________________

## Entity: Alert Rule

**Spec definition**: A named expression evaluated at regular intervals; transitions between
pending, firing, and resolved states.

**Kubernetes resource**: `PrometheusRule` CRD (managed by Prometheus Operator)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: <rule-group-name>
  namespace: observability
spec:
  groups:
    - name: <group>
      interval: 1m        # evaluation interval
      rules:
        - alert: <AlertName>
          expr: <PromQL expression>
          for: <pending duration>
          labels:
            severity: critical | warning | info
          annotations:
            summary: <human-readable summary>
            description: <detail>
```

**State machine**:

```
[inactive] → (expr true for < `for` duration) → [pending]
           → (expr true for >= `for` duration) → [firing]  → Alertmanager → Slack
[firing]   → (expr false) → [resolved] → Alertmanager → Slack (resolved message)
```

**Default rules**: kube-prometheus-stack ships a comprehensive default ruleset covering:
node disk, node memory, pod crash-looping, Kubernetes control plane, and Alertmanager self.

______________________________________________________________________

## Entity: Alert Notification

**Spec definition**: An outbound message sent to Slack when an alert fires or resolves.

**Kubernetes resource**: Alertmanager configuration (mounted from Secret)

**Secret structure** (sourced from 1Password via ExternalSecret):

```yaml
# Secret: alertmanager-slack-webhook
# Keys:
webhook-url: https://hooks.slack.com/services/...
```

**Alertmanager receiver config**:

```yaml
receivers:
  - name: slack
    slack_configs:
      - api_url: <webhook-url from secret>
        channel: '#alerts'
        send_resolved: true
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
route:
  receiver: slack
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
```

______________________________________________________________________

## Entity: Dashboard

**Spec definition**: A collection of visualization panels bound to metric queries.

**Kubernetes resource**: Grafana ConfigMap (provisioned automatically by kube-prometheus-stack)

**Provisioning mechanism**: Grafana sidecar watches ConfigMaps with label
`grafana_dashboard: "1"` across all namespaces and hot-loads them without restart.

**Default dashboards included** (from kube-prometheus-stack):

- Node Exporter / Nodes
- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace
- Kubernetes / Compute Resources / Pod
- Kubernetes / Networking / Cluster
- Prometheus / Overview
- Alertmanager / Overview

**Custom dashboard addition**: Create a ConfigMap with `grafana_dashboard: "1"` label in any
namespace — Grafana sidecar picks it up within ~30 seconds.

**Loki data source wiring** (required for FR-009 — metric-to-log navigation):

Grafana must have Loki pre-configured as an additional data source. This is set in the
kube-prometheus-stack HelmRelease values under `grafana.additionalDataSources`:

```yaml
grafana:
  additionalDataSources:
    - name: Loki
      type: loki
      url: http://loki.observability.svc.cluster.local:3100
      access: proxy
      isDefault: false
```

This must be set at deploy time — it cannot be configured after the fact without a Helm
upgrade. Without this, Grafana's Explore view will not have a Loki data source and FR-009
(metric-to-log navigation) and SC-007 (30-second log query) cannot be validated.

______________________________________________________________________

## Entity: Log Stream

**Spec definition**: A continuous sequence of log lines from a pod, tagged with namespace,
pod name, container name, and timestamp.

**Collection**: Alloy DaemonSet tails pod log files from the node filesystem
(`/var/log/pods/`) and forwards to Loki with structured labels.

**Loki label schema** (see also `contracts/loki-label-schema.md`):

- `namespace` — Kubernetes namespace
- `pod` — pod name
- `container` — container name
- `node_name` — node hostname
- `app` — value of `app.kubernetes.io/name` label (when present)

**Storage**:

- Location: Loki filesystem backend on a node-local PVC
- PVC size: ~10 GB
- Retention: 7 days
- Format: Loki chunk files + index (TSDB index)

**Query interface**: LogQL via Grafana's Explore view (Loki data source)

______________________________________________________________________

## Entity: Retention Policy

**Spec definition**: A configured maximum age for stored data, after which data is automatically
deleted.

| Data Type | Retention | Enforcement Mechanism                                      |
| --------- | --------- | ---------------------------------------------------------- |
| Metrics   | 30 days   | Prometheus `--storage.tsdb.retention.time=30d`             |
| Logs      | 7 days    | Loki `limits_config.retention_period: 168h` with compactor |

Both policies are enforced automatically by the respective components. No operator intervention
required.

______________________________________________________________________

## PersistentVolumeClaim Summary

| Component  | PVC Name Pattern                                           | Size | Access Mode   | Storage Class |
| ---------- | ---------------------------------------------------------- | ---- | ------------- | ------------- |
| Prometheus | `prometheus-db-prometheus-<helmrelease-name>-prometheus-0` | 30Gi | ReadWriteOnce | default       |
| Loki       | `storage-<helmrelease-name>-0`                             | 10Gi | ReadWriteOnce | default       |

The actual PVC names are derived from the HelmRelease name chosen at deploy time. For example,
if the HelmRelease is named `kube-prometheus-stack`, the Prometheus PVC becomes
`prometheus-db-prometheus-kube-prometheus-stack-prometheus-0`. Verify the exact names after
first deployment with `kubectl get pvc -n observability`.

Both PVCs use the cluster's default storage class (node-local). Prometheus PVC is managed by
the StatefulSet created by the Prometheus Operator. Loki PVC is managed by its own StatefulSet.
