# Hermes Agent Setup

[Hermes Agent](https://github.com/NousResearch/hermes-agent) runs its persistent gateway and Web Dashboard
in Kubernetes at `https://hermes.${SECRET_DOMAIN}`. Google SSO restricts browser access to the admin
group, and the dashboard additionally enforces its internal authentication gate.

## Dashboard Credentials (1Password)

Per the [Hermes Docker Setup guide](https://hermes-agent.nousresearch.com/docs/user-guide/docker), the
dashboard's authentication gate engages automatically whenever it binds to a non-loopback address
(`0.0.0.0`). The bundled username/password provider validates basic auth credentials.

Create a **Login** item named `hermes-agent` in the 1Password **homelab** vault:

- **Title**: `hermes-agent`
- **Website / URL**: `https://hermes.${SECRET_DOMAIN}`
- **Username**: `admin`
- **Password**: Generate or provide a strong password

External Secrets synchronizes the username and password from 1Password into `hermes-agent-secret`.
Reloader automatically restarts the pod when credentials change in 1Password.

## Architecture and Volumes

- **Image and Supervision**: The deployment runs `docker.io/nousresearch/hermes-agent:v0.21.6` with `gateway run`.
  A non-root launcher runs the image bootstrap hook, gateway, and dashboard directly, bypassing the root
  s6 entrypoint. If either process exits, the container exits and Kubernetes restarts it. Dynamic s6-supervised
  profile gateways are not supported by this deployment.
- **Persistent Data**: The `/opt/data` volume is the single source of truth for all Hermes state, including
  configuration, API keys (`.env`), sessions, persistent memory, and installed skills.
- **SQLite Database**: Sessions and memory are kept in `/opt/data/state.db`. The volume uses `storageClass: node-local`
  (ext4 on Talos), which fully supports SQLite's default WAL (Write-Ahead Logging) journal mode.
- **Concurrency**: A single replica uses `strategy: Recreate` because Hermes session stores and SQLite files
  do not support concurrent multi-instance writes.
- **User Identity**: The entire container runs as the unprivileged `hermes` user (`UID 10000`, `GID 10000`).
  The pod sets `fsGroup: 10000` to maintain proper file permissions on the persistent volume.

## Endpoints

- **Web Dashboard & Health Probes** (port `9119`): Serves the browser dashboard and acts as the remote backend
  for the Hermes Desktop app. Exposes the unauthenticated `/api/health` endpoint used by Kubernetes startup,
  liveness, and readiness probes. Routed at `/`.
- **OpenAI-Compatible API Server** (port `8642`): Exposes standard OpenAI API endpoints (such as `/v1/chat/completions`)
  authenticated via `API_SERVER_KEY`. Routed at `/v1`.

## CLI and Setup Commands

The Docker image includes a wrapper that automatically drops `docker exec` / `kubectl exec` calls to the
`hermes` user (UID 10000) so files created interactively maintain correct volume permissions:

```bash
# Run the interactive setup wizard inside the container
kubectl exec -it -n default deployment/hermes-agent -c app -- hermes setup

# Check agent status and running gateway services
kubectl exec -it -n default deployment/hermes-agent -c app -- hermes status --full

# View real-time agent logs
kubectl exec -it -n default deployment/hermes-agent -c app -- hermes logs --follow
```
