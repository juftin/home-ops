# Lunch Money Setup

[Lunch Money](https://github.com/juftin/lunchmoney-app) runs its MCP server, REST API, and
financial dashboard in Kubernetes at `https://lunchmoney.${SECRET_DOMAIN}` internally on LAN
and privately via Tailscale at `https://lunchmoney.<tailnet-DNS-suffix>`.

The deployment uses PostgreSQL for persistent data caching, Valkey for distributed locking, and a
dedicated scheduler running hourly synchronizations.

## 1Password Configuration

Create an item named `lunchmoney` in the 1Password **homelab** vault with the following custom fields:

| Field                     | Type     | Required | Description                                                    |
| ------------------------- | -------- | -------- | -------------------------------------------------------------- |
| `LUNCHMONEY_ACCESS_TOKEN` | Password | Yes      | Lunch Money developer API access token                         |
| `POSTGRES_PASSWORD`       | Password | Yes      | Password for the PostgreSQL database user (`lunchmoney`)       |
| `LUNCHMONEY_APP_API_KEY`  | Password | No       | Optional key required for REST API calls and metrics endpoints |

The `lunchmoney` `ExternalSecret` syncs these credentials into `lunchmoney-secret` in the `lunchmoney` namespace.
Reloader automatically restarts workloads when secrets change.

## Network Access

Lunch Money is configured with private access only and is not exposed to the public internet:

1. **Internal LAN Access**:
   Routed through the `envoy-internal` Gateway at `https://lunchmoney.${SECRET_DOMAIN}` (and `lunchmoney-app.${SECRET_DOMAIN}`).
   Internal DNS is resolved via `k8s-gateway`.

2. **Tailscale Access**:
   The Tailscale Kubernetes operator provisions a private HTTPS endpoint at
   `https://lunchmoney.<tailnet-DNS-suffix>` pointing directly to the `lunchmoney` service on port 8000.
   Tailnet devices can access the dashboard or connect remote MCP clients directly using `https://lunchmoney.<tailnet-DNS-suffix>/mcp`.

## Architecture & Workloads

All components run under the `lunchmoney` Helm release in the `lunchmoney` namespace:

- **`lunchmoney` (Web App)**:
  Runs Gunicorn and Uvicorn workers serving the REST API, MCP endpoint (`/mcp`), and financial dashboard (`/`).
  An init container verifies PostgreSQL and Valkey connectivity before the app starts.
- **`lunchmoney-scheduler` (Sync Scheduler)**:
  Dedicated single-replica worker running `lunchmoney-app schedule` for recurring background synchronization.
- **`lunchmoney-db` (PostgreSQL 17)**:
  Backed by a 5Gi `node-local` PersistentVolumeClaim for transaction and metadata storage.
- **`lunchmoney-valkey` (Valkey 8)**:
  Provides distributed lock coordination between the web application and the scheduler.

## Verification

After syncing ArgoCD, verify the deployment:

```bash
# Check secret synchronization
kubectl get externalsecret lunchmoney -n lunchmoney

# Check pod statuses
kubectl get pods -n lunchmoney -l app.kubernetes.io/instance=lunchmoney

# Check internal HTTPRoute
kubectl get httproute lunchmoney -n lunchmoney

# Check Tailscale Ingress
kubectl get ingress lunchmoney-tailscale -n lunchmoney
```
