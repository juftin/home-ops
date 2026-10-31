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

Camply is deployed using the dedicated `camply-web` Helm chart (`oci://ghcr.io/juftin/charts/camply-web`).
Frontend, API, worker, beat, and migration Job containers use the versioned `ghcr.io/juftin/camply-web` application image:

- **Frontend** (`camply-frontend`): React + Vite single-page application served via Nginx on port `8080`
  with gzip compression and immutable asset caching. `camply serve frontend` locates the bundled UI
  and renders the packaged Nginx configuration. `CAMPLY_BACKEND_URL: http://camply-backend:8000`
  directs its `/api/` proxy to the API Service.
- **Backend API** (`camply-backend`): FastAPI application running under Gunicorn on port `8000` with
  `GZipMiddleware` response compression. Exposes `/api/ping` for dependency-independent liveness and
  `/api/health` for database-verified readiness.
- **Worker** (`camply-worker`): Celery worker consuming tasks from the `celery` queue for campsite
  availability searches. `camply serve worker` defaults to this queue and concurrency 4.
- **Beat** (`camply-beat`): Singleton scheduler running `camply serve beat --sync-providers` with `Recreate`
  strategy, enqueuing an initial provider catalog sync before starting periodic schedules.
- **Database** (`camply-postgresql`): PostgreSQL 17 attached to the existing 10Gi `node-local` persistent volume claim (`camply-db-data`).
- **Cache/Broker** (`camply-valkey`): Valkey instance serving as Celery message broker and result backend, attached to `camply-valkey-data`.
- **Monitoring** (`camply-prometheus`): Isolated Prometheus instance attached to `camply-prometheus-data`, scraping backend and worker metrics to power Camply's built-in Admin Trends dashboard.

## Migration Startup Barrier

A release-specific Kubernetes Job (`camply-migrate-<hash>`) runs Alembic migrations with database checkpointing in the `camply_helm_migrations` table.
Backend, worker, and beat pods mount credentials only inside their `wait-for-migrations` init containers using a scoped `camply-migration-wait` ServiceAccount and Role:

- The init container watches the specific release migration Job until its `Complete=True` condition succeeds.
- Worker and beat init containers additionally verify PostgreSQL and Valkey TCP connectivity and the API's `/api/health` endpoint.
- Database checkpoints allow rollbacks without rerunning older Alembic revisions against newer schemas, and avoid needing ArgoCD sync waves.

## Health checks

Frontend and backend use native Kubernetes HTTP probes. Worker and beat use matching `camply serve healthcheck <role>` commands as exec probes:

| Role     | Probe type | Kubernetes probe                              | What it verifies                                                                   |
| -------- | ---------- | --------------------------------------------- | ---------------------------------------------------------------------------------- |
| Frontend | HTTP       | HTTP GET `/healthz` on port `8080`            | Nginx responds on the pod IP, independently of the API upstream                    |
| Backend  | HTTP       | HTTP GET `/api/ping` on port `8000`           | Liveness probe; verifies API process responds without dependency latency           |
| Backend  | HTTP       | HTTP GET `/api/health` on port `8000`         | Startup & readiness probe; verifies database connectivity within a 2-second budget |
| Worker   | Exec       | `camply serve healthcheck worker --timeout 5` | Directed Celery ping to this pod's `celery@<hostname>` node through Valkey         |
| Beat     | Exec       | `camply serve healthcheck beat`               | Heartbeat loop marker freshness (`/tmp/camply-beat-health.json`) from a live PID   |

PostgreSQL and Valkey keep their native health checks (`pg_isready` and `valkey-cli ping`).

## Shutdown

Application pods have a 60-second termination grace period. Python roles receive Kubernetes'
default SIGTERM. The frontend's pre-stop hook sends SIGQUIT to Nginx and waits for it to exit,
allowing graceful connection draining before Kubernetes sends SIGTERM.

## Ingress and Access

- **Public Route**: Exposes `camply.${SECRET_DOMAIN}` through Cloudflare Tunnel and the `envoy-external`
  Gateway. Public traffic reaches the application directly, using Camply's application-level
  authentication (session login or open access). The Cloudflare Tunnel routes traffic matching
  `*.${SECRET_DOMAIN}` directly to `envoy-external`.
- The HTTPRoute directs `/api` traffic to `camply-backend:8000` and all other traffic (`/`) to `camply-frontend:8080`.
