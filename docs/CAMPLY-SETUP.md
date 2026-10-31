# Camply Setup

[Camply](https://github.com/juftin/camply), the campsite finder ⛺️, runs in Kubernetes at
`https://camply.${SECRET_DOMAIN}` as a public web application with automated campsite search
and notification scheduling.

## Credentials (1Password)

Create a **Secure Note** or **Login** item named `camply-home-ops` in the 1Password **homelab** vault:

- **Title**: `camply-home-ops`
- **POSTGRES_PASSWORD**: Strong generated password for the PostgreSQL database
- **CAMPLY_SESSION_SECRET**: Random secret string (at least 32 characters) for session signing
- **CAMPLY_LOGIN_USERNAME**: Username for in-app session login (e.g. `admin` or your personal username)
- **CAMPLY_LOGIN_PASSWORD**: Password for in-app session login

Authentication uses `CAMPLY_AUTH_MODE: session`. Log in with your configured `CAMPLY_LOGIN_USERNAME` and `CAMPLY_LOGIN_PASSWORD`.

External Secrets synchronizes these values into `camply-home-ops` in the `default` namespace.
Reloader automatically restarts the deployments when secrets change in 1Password.

## Architecture and Components

Camply is deployed using the `app-template` chart with dedicated controllers. Frontend, API,
worker, beat, and their wait init containers share `ghcr.io/juftin/camply-web:latest`:

- **Frontend** (`camply-frontend`): React + Vite single-page application served via Nginx on port `8080`
  with gzip compression and immutable asset caching. `camply serve frontend` locates the bundled UI
  and renders the packaged Nginx configuration. `CAMPLY_BACKEND_URL: http://camply-backend:8000`
  directs its `/api/` proxy to the API Service. The upstream default is `http://backend:8000`.
- **Backend API** (`camply-backend`): FastAPI application running under Gunicorn on port `8000` with
  `GZipMiddleware` response compression. `camply serve backend` applies Alembic database migrations
  on startup before serving the API. Exposes
  `/api/health` for health probes.
- **Worker** (`camply-worker`): Celery worker consuming tasks from the `celery` queue for campsite
  availability searches. `camply serve worker` defaults to this queue and concurrency 4.
- **Beat** (`camply-beat`): `camply serve beat --sync-providers` enqueues an initial provider
  catalog sync, then starts the scheduler for periodic catalog sync and poller tasks.
- **Database** (`camply-db`): PostgreSQL 17 with a 10Gi `node-local` persistent volume claim.
- **Cache/Broker** (`camply-valkey`): Valkey 8 instance serving as Celery message broker and result backend.
- **Monitoring** (`camply-prometheus`): Isolated Prometheus 3 instance with a 5Gi `node-local` persistent volume, scraping backend and worker metrics to power Camply's built-in Admin Trends dashboard.

Worker and beat share init containers that check PostgreSQL and Valkey and run
`camply serve healthcheck backend --url http://camply-backend:8000/api/health --timeout 2`
until the API responds successfully. API checks retry at two-second intervals and fail after
60 attempts. Only the backend applies migrations, before launching the API.

During a full ArgoCD sync, the backend Deployment is in wave `0`; worker and beat Deployments
are in wave `1`. ArgoCD waits for the new backend rollout to become healthy before updating
worker/beat, preventing an old API pod's health response from allowing their rollout before the
new backend finishes migrating. The init check also covers subsequent pod restarts. Use a full
Camply app sync for coordinated upgrades; selectively syncing worker/beat bypasses this rollout
ordering.

The beat CLI's opt-in `--sync-providers` flag dispatches the catalog task with a ten-minute
expiry before replacing the process with Celery beat. Dispatch failure stops startup; successful
dispatch queues asynchronous work without waiting for ingestion to complete. Bare
`camply serve beat` does not dispatch an initial sync.

## Health checks

Frontend and backend use native Kubernetes HTTP probes for startup, liveness, and readiness.
Worker and beat use the matching `camply serve healthcheck <role>` commands as exec probes.
HTTP probes have a three-second timeout; exec probes have a ten-second Kubernetes timeout,
with a five-second internal timeout for the worker ping. The HTTP CLI commands remain useful
for manual diagnostics, and the API-wait init container uses the custom-URL backend command.

| Role     | Kubernetes probe                              | What it verifies                                                             |
| -------- | --------------------------------------------- | ---------------------------------------------------------------------------- |
| Frontend | HTTP GET `/healthz` on port `8080`            | Nginx responds on the pod IP, independently of the API upstream              |
| Backend  | HTTP GET `/api/health` on port `8000`         | API HTTP liveness on the pod IP                                              |
| Worker   | `camply serve healthcheck worker --timeout 5` | A directed Celery ping to this pod's `celery@<hostname>` node through Valkey |
| Beat     | `camply serve healthcheck beat`               | A fresh scheduling-loop heartbeat from a live local PID                      |

Worker and beat startup probes allow 30 failures at ten-second intervals. Their readiness
checks run every 30 seconds and fail after three unsuccessful checks. Worker liveness requires
six consecutive failures at 30-second intervals before restart, allowing longer recovery for
its broker-dependent ping; beat liveness requires three. Worker readiness reports control
responsiveness and broker connectivity; it does not pause Celery's queue consumption.

The beat launcher automatically selects its heartbeat scheduler with a maximum 30-second loop
sleep. Serving and probing share `CAMPLY_BEAT_HEALTH_FILE=/tmp/camply-beat-health.json` inside
the beat container. The probe rejects a marker older than 60 seconds or a dead PID; startup
clears old state and clean shutdown removes the marker. Keep this file local to the container,
and retain the launcher's scheduler and interval defaults. A fresh marker verifies scheduler
progress; successful task publication and completion remain separate checks.

PostgreSQL and Valkey keep their existing native probes. The API probe does not check either
service, so the separate infrastructure checks and rollout ordering remain necessary. The
packaged Nginx configuration includes HTTPS upstream SNI support when an HTTPS
`CAMPLY_BACKEND_URL` is configured.

## Shutdown

Application pods have a 60-second termination grace period. Python roles receive Kubernetes'
default SIGTERM. The frontend's pre-stop hook sends SIGQUIT to Nginx and waits for it to exit,
allowing graceful connection draining before Kubernetes sends SIGTERM.

The frontend proxy, ingress, and Prometheus use the existing `camply-backend` Service.
There is no application-specific Nginx ConfigMap or asset-path override to maintain.

## Upgrade prerequisite

This deployment requires the unified image and CLI entrypoints introduced by
[camply-web#261](https://github.com/juftin/camply-web/pull/261). Before deploying, confirm that it
has merged and `ghcr.io/juftin/camply-web:latest` has been published with all four serving roles,
the role-specific health commands, heartbeat scheduler, `CAMPLY_BACKEND_URL`, and
`--sync-providers`. The health interface is reviewed against upstream commit
[`b18b991`](https://github.com/juftin/camply-web/commit/b18b99180251a853c4113946d40ab56b8560563d).
Validate with `task lint` and `task dev:validate` (or `task dev:validate:ci` without the age key).
After reconciliation, verify the frontend `/healthz`, API `/api/health`, session login, worker
metrics, initial provider-sync dispatch, and all four CLI health checks from their matching
containers. Check beat's heartbeat freshness and worker targeting as well. Exercise the frontend Service's `/api/health` proxy
as well; the public HTTPRoute sends `/api` traffic directly to `camply-backend`.

## Ingress and Access

- **Public Route**: Exposes `camply.${SECRET_DOMAIN}` through Cloudflare Tunnel and the `envoy-external`
  Gateway. Public traffic reaches the application directly, using Camply's application-level
  authentication (session login or open access). The Cloudflare Tunnel routes traffic matching
  `*.${SECRET_DOMAIN}` directly to `envoy-external`.
