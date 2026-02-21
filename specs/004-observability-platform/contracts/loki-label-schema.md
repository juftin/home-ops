# Contracts: Loki Label Schema

## Purpose

Defines the canonical label set applied to all log streams collected by Alloy and stored in
Loki. Log queries in Grafana MUST use these labels for filtering.

## Canonical Label Set

All log streams ingested by Alloy carry the following labels:

| Label       | Source                             | Example Value       | Notes                     |
| ----------- | ---------------------------------- | ------------------- | ------------------------- |
| `namespace` | Kubernetes pod metadata            | `default`           | Always present            |
| `pod`       | Kubernetes pod metadata            | `echo-7d9f8b-xk2p9` | Always present            |
| `container` | Kubernetes container spec          | `echo`              | Always present            |
| `node_name` | Kubernetes node name               | `node-01`           | Always present            |
| `app`       | `app.kubernetes.io/name` pod label | `echo`              | Present when label exists |
| `stream`    | stdout or stderr                   | `stdout`            | Always present            |

## High-Cardinality Label Avoidance

Labels MUST NOT include high-cardinality values such as:

- Request IDs
- User IDs
- IP addresses
- Timestamps (already in the log line itself)

High-cardinality labels cause Loki index bloat and are prohibited per Loki best practices.

## LogQL Query Examples

**All logs from a namespace**:

```logql
{namespace="default"}
```

**Logs from a specific pod**:

```logql
{namespace="default", pod="echo-7d9f8b-xk2p9"}
```

**Error lines from an app**:

```logql
{app="myapp"} |= "error"
```

**Logs from all pods on a node**:

```logql
{node_name="node-01"}
```

## Retention

All log streams are retained for 7 days regardless of namespace or app. Loki's compactor
enforces this automatically via `limits_config.retention_period: 168h`.

## Grafana Integration

The Loki data source is pre-configured in Grafana as part of the kube-prometheus-stack
deployment. The data source name is `Loki`. Metric-to-log navigation (FR-009) is enabled
via Grafana's "derived fields" configuration linking Prometheus metric labels to Loki label
filters.
