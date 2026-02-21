# Quickstart: Observability Platform

## Overview

This guide covers what the observability platform deploys, what prerequisites are required,
what secrets must exist in 1Password before deploying, and how to verify the platform is
working after deployment.

## What Gets Deployed

| Component             | Helm Chart           | Purpose                                                              |
| --------------------- | -------------------- | -------------------------------------------------------------------- |
| kube-prometheus-stack | prometheus-community | Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics |
| Loki                  | grafana              | Log aggregation and storage                                          |
| Alloy                 | grafana              | Log collection DaemonSet (ships pod logs to Loki)                    |

All components deploy to the `observability` namespace.

## Prerequisites

- [ ] Flux is reconciling from `main` (or your feature branch during testing)
- [ ] External Secrets Operator is running and the `onepassword` ClusterSecretStore is healthy
- [ ] The `observability` namespace exists (`kubectl get ns observability`)
- [ ] The `envoy-external` Gateway exists in the `network` namespace
- [ ] Default storage class is available (`kubectl get sc`)

## 1Password Secrets Required

Create the following items in 1Password **before** deploying. The ExternalSecret in
`kube-prometheus-stack/app/externalsecret.yaml` references these by item name.

### Item: `grafana-admin-creds`

| Field      | Value                                |
| ---------- | ------------------------------------ |
| `username` | `admin` (or your preferred username) |
| `password` | A strong random password             |

### Item: `alertmanager-slack-webhook`

| Field         | Value                                                                          |
| ------------- | ------------------------------------------------------------------------------ |
| `webhook-url` | Your Slack incoming webhook URL (e.g., `https://hooks.slack.com/services/...`) |

**How to create a Slack incoming webhook**:

1. Go to your Slack workspace → Apps → Incoming Webhooks
2. Create a new webhook pointing at your `#alerts` channel (or preferred channel)
3. Copy the webhook URL into the 1Password item above

## Configuration Variables

The following variables are injected from the `cluster-secrets` Secret at deploy time (already
configured for this cluster):

| Variable           | Used By                    | Value        |
| ------------------ | -------------------------- | ------------ |
| `${SECRET_DOMAIN}` | Grafana HTTPRoute hostname | `juftin.dev` |

Grafana will be accessible at `https://grafana.juftin.dev` after deployment.

## Deployment Order

Flux reconciles resources in this order (controlled by `dependsOn` in ks.yaml files):

1. **kube-prometheus-stack** — deploys first; installs CRDs (PrometheusRule, ServiceMonitor, etc.)
2. **Loki** — deploys after kube-prometheus-stack CRDs are available
3. **Alloy** — deploys after Loki is ready (needs Loki endpoint to push logs to)

## Verification Steps

### 1. Check all pods are running

```bash
kubectl get pods -n observability
```

Expected pods:

- `prometheus-kube-prometheus-stack-prometheus-0` (Prometheus)
- `alertmanager-kube-prometheus-stack-alertmanager-0` (Alertmanager)
- `kube-prometheus-stack-grafana-*` (Grafana)
- `kube-prometheus-stack-node-exporter-*` (one per node)
- `kube-prometheus-stack-kube-state-metrics-*`
- `loki-0` (Loki)
- `alloy-*` (one per node)

### 2. Verify Grafana is accessible

Navigate to `https://grafana.juftin.dev` — should display the Grafana login page.
Log in with the credentials from your `grafana-admin-creds` 1Password item.

### 3. Verify pre-built dashboards load

In Grafana → Dashboards → Browse → look for folders:

- "Kubernetes / Compute Resources"
- "Node Exporter"
- "Prometheus"

Open any dashboard — panels should populate within 1–2 scrape intervals (30–60 seconds).

### 4. Verify all scrape targets are up

Grafana → Explore → Select "Prometheus" data source → query:

```promql
up
```

All targets should return `1`. Any `0` indicates a scrape failure.

### 5. Verify log collection

Grafana → Explore → Select "Loki" data source → query:

```logql
{namespace="observability"} | limit 20
```

Should return recent log lines from observability components within a few seconds.

### 6. Test alert firing

To verify Alertmanager → Slack is working, trigger a manual test alert:

```bash
kubectl exec -n observability \
  alertmanager-kube-prometheus-stack-alertmanager-0 -- \
  amtool alert add alertname=TestAlert severity=info \
    --alertmanager.url=http://localhost:9093
```

Check your Slack `#alerts` channel for the notification. Then resolve it:

```bash
kubectl exec -n observability \
  alertmanager-kube-prometheus-stack-alertmanager-0 -- \
  amtool silence add alertname=TestAlert --duration=1m \
    --alertmanager.url=http://localhost:9093
```

## Storage Notes

| Component  | PVC                              | Size | Retention |
| ---------- | -------------------------------- | ---- | --------- |
| Prometheus | `prometheus-db-prometheus-kps-0` | 30Gi | 30 days   |
| Loki       | `storage-loki-0`                 | 10Gi | 7 days    |

Both PVCs use the cluster's default storage class (node-local). Data survives pod restarts and
reboots. Data does **not** survive permanent loss of the node hosting the PVC — this is a known
limitation of the initial deployment (see spec Assumptions; replicated storage is a future goal).

## Troubleshooting

**Grafana shows "no data"**: Check Prometheus targets at Grafana → Explore → `up` query.
If targets are missing, check ServiceMonitor/PodMonitor resources.

**Slack alerts not arriving**: Check Alertmanager config:

```bash
kubectl exec -n observability \
  alertmanager-kube-prometheus-stack-alertmanager-0 -- \
  amtool config show --alertmanager.url=http://localhost:9093
```

Verify the webhook URL matches your Slack incoming webhook.

**Loki returns no logs**: Check Alloy pods are running on all nodes and are not in CrashLoop.
Check Alloy logs: `kubectl logs -n observability -l app.kubernetes.io/name=alloy`.
