# Camply Setup

[Camply](https://github.com/juftin/camply), the campsite finder ⛺️, runs in Kubernetes at
`https://camply.${SECRET_DOMAIN}` and privately via Tailscale at
`https://camply.<tailnet-DNS-suffix>`. Google SSO restricts browser access to the admin group,
and the app provides automated campsite search and notification scheduling.

## Credentials (1Password)

Create a **Secure Note** or **Login** item named `camply` in the 1Password **homelab** vault:

- **Title**: `camply`
- **POSTGRES_PASSWORD**: Strong generated password for the PostgreSQL database
- **CAMPLY_SESSION_SECRET**: Random secret string (at least 32 characters) for session signing

External Secrets synchronizes these values into `camply-secret` in the `default` namespace.
Reloader automatically restarts the deployments when secrets change in 1Password.

## Architecture and Components

Camply is deployed using the `app-template` chart with dedicated controllers:

- **Frontend** (`camply-frontend`): React + Vite single-page application served via Nginx on port `8080`.
  Reverse-proxies `/api/` to `camply-backend:8000` with custom Nginx configMap.
- **Backend API** (`camply-backend`): FastAPI application running under Gunicorn on port `8000`.
  Applies Alembic database migrations on startup. Exposes `/api/health` for health probes.
- **Worker** (`camply-worker`): Celery worker consuming tasks from the `celery` queue for campsite
  availability searches.
- **Beat** (`camply-beat`): Celery beat scheduler for periodic provider catalog sync and poller tasks.
- **Database** (`camply-db`): PostgreSQL 17 with a 10Gi `node-local` persistent volume claim.
- **Cache/Broker** (`camply-valkey`): Valkey 8 instance serving as Celery message broker and result backend.

## Ingress and Access

1. **OAuth Administration Route**: Exposes `camply.${SECRET_DOMAIN}` through Cloudflare Tunnel and the
   `envoy-oauth-admin` Gateway with Google SSO protection.
2. **Tailscale Ingress**: Exposes `https://camply.<tailnet-DNS-suffix>` for direct, low-latency access
   from any authenticated Tailscale device without public exposure.
