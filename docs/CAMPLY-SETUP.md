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
worker, beat, and their wait init containers share `ghcr.io/juftin/camply:latest`:

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

Worker and beat share a wait init container that checks PostgreSQL and Valkey, then waits for
`http://camply-backend:8000/api/health`. The API becomes available after migrations finish, so
workers cannot process tasks against an unmigrated database. Only the backend applies migrations.

The beat CLI's opt-in `--sync-providers` flag dispatches the catalog task with a ten-minute
expiry before replacing the process with Celery beat. Dispatch failure stops startup; successful
dispatch queues asynchronous work without waiting for ingestion to complete. Bare
`camply serve beat` does not dispatch an initial sync.

Application pods have a 60-second termination grace period. Python roles receive Kubernetes'
default SIGTERM. The frontend's pre-stop hook sends SIGQUIT to Nginx and waits for it to exit,
allowing graceful connection draining before Kubernetes sends SIGTERM.

The frontend proxy, ingress, and Prometheus use the existing `camply-backend` Service.
There is no application-specific Nginx ConfigMap or asset-path override to maintain.

## Upgrade prerequisite

This deployment requires the unified image and CLI entrypoints introduced by
[camply-web#261](https://github.com/juftin/camply-web/pull/261). Before deploying, confirm that it
has merged and `ghcr.io/juftin/camply:latest` has been published with all four serving roles.
Validate with `task lint` and `task dev:validate` (or `task dev:validate:ci` without the age key).
After reconciliation, verify the frontend `/healthz`, API `/api/health`, session login, worker
metrics, and initial provider-sync dispatch. Exercise the frontend Service's `/api/health` proxy
as well; the public HTTPRoute sends `/api` traffic directly to `camply-backend`.

## Ingress and Access

- **Public Route**: Exposes `camply.${SECRET_DOMAIN}` through Cloudflare Tunnel and the `envoy-external`
  Gateway. Public traffic reaches the application directly, using Camply's application-level
  authentication (session login or open access). The Cloudflare Tunnel routes traffic matching
  `*.${SECRET_DOMAIN}` directly to `envoy-external`.
