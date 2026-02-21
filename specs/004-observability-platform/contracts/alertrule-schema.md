# Contracts: Alert Rule Schema

## Purpose

Defines the schema and naming conventions for PrometheusRule resources added to this cluster.
All alert rules MUST follow this schema to integrate with the Alertmanager Slack receiver.

## PrometheusRule Schema

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: <descriptive-kebab-case-name>
  namespace: observability              # MUST be in observability namespace
  labels:
    app.kubernetes.io/name: <app>       # SHOULD match the monitored app
spec:
  groups:
    - name: <group-name>                # e.g., "node.rules", "app-name.alerts"
      interval: 1m                      # evaluation interval; SHOULD be 1m or 5m
      rules:
        - alert: <AlertName>            # PascalCase, descriptive
          expr: <PromQL expression>     # MUST be a valid PromQL expression
          for: <duration>              # pending duration before firing (e.g., 5m, 15m)
          labels:
            severity: critical          # MUST be one of: critical | warning | info
          annotations:
            summary: <one-line summary>
            description: <detail including {{ $labels.* }} template variables>
            runbook_url: <optional link to remediation steps>
```

## Severity Definitions

| Severity   | Meaning                                            | Example                   |
| ---------- | -------------------------------------------------- | ------------------------- |
| `critical` | Requires immediate action; cluster or data at risk | Node down, disk >90%      |
| `warning`  | Degraded state; action needed soon                 | Pod restarting, disk >75% |
| `info`     | Noteworthy event; no immediate action needed       | Deployment rolled out     |

## Alertmanager Routing

All alerts route to the default `slack` receiver. The Slack message template includes:

- Alert name (`{{ .GroupLabels.alertname }}`)
- Severity label
- Description annotation
- Firing/resolved status

## Default Rules (from kube-prometheus-stack)

The following rule groups are pre-installed and MUST NOT be duplicated:

| Rule Group           | Coverage                                |
| -------------------- | --------------------------------------- |
| `node.rules`         | Node CPU, memory, disk, network         |
| `kubernetes-absent`  | Control plane component availability    |
| `kubernetes-apps`    | Pod crash-looping, pending, OOMKilled   |
| `kubernetes-storage` | PVC capacity                            |
| `alertmanager.rules` | Alertmanager self-health                |
| `prometheus`         | Prometheus self-health, scrape failures |

## Adding Custom Rules

Create a `PrometheusRule` in the `observability` namespace. The Prometheus Operator discovers
it automatically within one evaluation interval (≤1 minute).
