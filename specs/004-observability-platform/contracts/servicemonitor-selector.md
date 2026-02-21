# Contracts: ServiceMonitor Selector Pattern

## Purpose

Defines the selector contract that applications MUST follow to have their metrics scraped
by Prometheus automatically (FR-008).

## Global Selector Configuration

Prometheus (via kube-prometheus-stack) is configured with:

```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
```

This means: **any** `ServiceMonitor`, `PodMonitor`, or `PrometheusRule` in **any namespace**
is automatically discovered — no additional selector labels required.

## ServiceMonitor Contract

Applications exposing a `Service` with a metrics port MUST create a `ServiceMonitor`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: <app-name>
  namespace: <app-namespace>      # can be any namespace
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: <app-name>   # MUST match the Service's labels
  endpoints:
    - port: metrics                         # MUST match the port name on the Service
      interval: 30s                         # SHOULD use 30s (global default)
      path: /metrics                        # default; override if app uses different path
  namespaceSelector:
    matchNames:
      - <app-namespace>
```

## PodMonitor Contract

Applications without a Service (e.g., DaemonSets with no Service) MUST use a `PodMonitor`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: <app-name>
  namespace: <app-namespace>
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: <app-name>
  podMetricsEndpoints:
    - port: metrics
      interval: 30s
      path: /metrics
  namespaceSelector:
    matchNames:
      - <app-namespace>
```

## Required Labels on Metrics Endpoints

Scrape targets SHOULD expose the following labels for dashboard compatibility:

- `namespace` (auto-injected by Prometheus relabeling)
- `pod` (auto-injected)
- `container` (auto-injected)
- `job` (set to `<namespace>/<service-name>` by default)

## Validation

After deploying a new ServiceMonitor, verify it appears in Prometheus targets:

- Navigate to `grafana.${SECRET_DOMAIN}` → Explore → Prometheus data source
- Query: `up{job="<namespace>/<service-name>"}` — should return `1`
