# Lunch Money Setup

[Lunch Money](https://github.com/juftin/lunchmoney-app) runs its MCP server, REST API, and
financial dashboard in Kubernetes at `https://lunchmoney.${SECRET_DOMAIN}` internally on LAN
and privately via Tailscale at `https://lunchmoney.<tailnet-DNS-suffix>`.

The deployment uses PostgreSQL for persistent data caching, Valkey for distributed locking, and a
dedicated scheduler running hourly synchronizations.

## 1Password Configuration

Create an item named `lunchmoney` in the 1Password **homelab** vault with the following custom fields:

| Field                     | Type     | Required | Description                                                                      |
| ------------------------- | -------- | -------- | -------------------------------------------------------------------------------- |
| `LUNCHMONEY_ACCESS_TOKEN` | Password | Yes      | Lunch Money developer API access token                                           |
| `POSTGRES_PASSWORD`       | Password | Yes      | Password for the PostgreSQL database user (`lunchmoney`)                         |
| `LUNCHMONEY_APP_API_KEY`  | Password | Yes      | Required key for all data endpoints, including REST, MCP, dashboard, and metrics |

The `lunchmoney` `ExternalSecret` syncs these credentials into `lunchmoney-secret` in the `default` namespace.
Reloader automatically restarts workloads when secrets change. Populate `LUNCHMONEY_APP_API_KEY`
with a strong random key before deploying. A missing or empty key prevents the authentication
proxy from starting. Do not put the value in Git, URLs, or command history.

## Network Access

Lunch Money is configured with private access only and is not exposed to the public internet:

1. **Internal LAN Access**:
   Routed through the `envoy-internal` Gateway at `https://lunchmoney.${SECRET_DOMAIN}` (and `lunchmoney-app.${SECRET_DOMAIN}`).
   Internal DNS is resolved via `k8s-gateway`.

2. **Tailscale Access**:
   The Tailscale Kubernetes operator provisions a private HTTPS endpoint at
   `https://lunchmoney.<tailnet-DNS-suffix>` pointing to the `lunchmoney-app` service on port 8000.
   Tailnet devices can access the dashboard or connect remote MCP clients directly using `https://lunchmoney.<tailnet-DNS-suffix>/mcp`.

## Authentication

Both LAN and Tailscale endpoints require an `X-API-Key` header. Configure that header in
remote MCP clients and OpenClaw using the key from 1Password. Requests without the header,
with a wrong key, or with a key in a query parameter are rejected. `/health` and `/ready`
remain public for orchestration and return no financial data.

This also protects the dashboard. A browser without a configured header receives HTTP 401;
this deployment does not add an interactive browser login or persist a key in frontend code.
Use a client capable of supplying the header. Google SSO on other apps does not authorize
Lunch Money. The documented Tailscale grant should restrict access to intended users.

The app's native key middleware intentionally skips `/mcp`. An nginx sidecar authenticates
all data requests through an internal subrequest to the native key-protected `/api` endpoint
before proxying. That endpoint is cheap and does not fetch financial data. A failed auth
backend fails closed. The required key is supplied to both containers; nginx refuses to start
when it is empty. This adapter relies on the pinned app's `/api` authentication contract;
verify it when upgrading the app. Health routes are the only public proxy paths.

The Service retains port **8000** for client compatibility and forwards to proxy port **8080**.
Ingress NetworkPolicy blocks the raw app port 8000 and limits proxy callers to the internal
Gateway, the matching Tailscale proxy, and OpenClaw. PostgreSQL/Valkey accept ingress only
from this release's workloads. OpenClaw's egress exception targets proxy port 8080 after
Service translation; it still calls the Service at port 8000.

## Architecture & Workloads

All components run under the `lunchmoney` Helm release in the `default` namespace:

- **`lunchmoney` (Web App)**:
  Runs an nginx key-checking sidecar in front of Gunicorn and Uvicorn workers serving the REST API, MCP endpoint (`/mcp`), and financial dashboard (`/`).
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
kubectl get externalsecret lunchmoney -n default

# Check pod statuses
kubectl get pods -n default -l app.kubernetes.io/instance=lunchmoney

# Check internal HTTPRoute
kubectl get httproute lunchmoney -n default

# Check Tailscale Ingress
kubectl get ingress lunchmoney-tailscale -n default
```
