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

Camply is deployed using the `app-template` chart with dedicated controllers:

- **Frontend** (`camply-frontend`): React + Vite single-page application served via Nginx on port `8080`
  with gzip compression and immutable asset caching. Reverse-proxies `/api/` to `camply-backend:8000`.
- **Backend API** (`camply-backend`): FastAPI application running under Gunicorn on port `8000` with
  `GZipMiddleware` response compression. Applies Alembic database migrations on startup. Exposes
  `/api/health` for health probes.
- **Worker** (`camply-worker`): Celery worker consuming tasks from the `celery` queue for campsite
  availability searches.
- **Beat** (`camply-beat`): Celery beat scheduler for periodic provider catalog sync and poller tasks.
- **Database** (`camply-db`): PostgreSQL 17 with a 10Gi `node-local` persistent volume claim.
- **Cache/Broker** (`camply-valkey`): Valkey 8 instance serving as Celery message broker and result backend.
- **Monitoring** (`camply-prometheus`): Isolated Prometheus 3 instance with a 5Gi `node-local` persistent volume, scraping backend and worker metrics to power Camply's built-in Admin Trends dashboard.

Worker, beat, and the initial provider-sync call use `celery -A camply.worker.celery_app`.
The backend image now packages Python modules under `camply`; the old
`worker.celery_app` entry point is no longer available. Keep these Helm arguments
aligned with the image when upgrading. The API uses the image's default command.

## Ingress and Access

- **Public Route**: Exposes `camply.${SECRET_DOMAIN}` through Cloudflare Tunnel and the `envoy-external`
  Gateway. Public traffic reaches the application directly, using Camply's application-level
  authentication (session login or open access). The Cloudflare Tunnel routes traffic matching
  `*.${SECRET_DOMAIN}` directly to `envoy-external`.
