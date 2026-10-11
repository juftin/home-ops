# Hermes Agent Setup

[Hermes Agent](https://github.com/NousResearch/hermes-agent) runs its persistent gateway and Web Dashboard
in Kubernetes at `https://hermes.${SECRET_DOMAIN}`. Google SSO restricts browser access to the admin
group, and the dashboard additionally enforces its internal authentication gate.

## Dashboard Password & 1Password Sync

Per the [Hermes Docker Setup guide](https://hermes-agent.nousresearch.com/docs/user-guide/docker), the
dashboard's authentication gate engages automatically whenever it binds to a non-loopback address
(`0.0.0.0`). The bundled username/password provider is enabled with `HERMES_DASHBOARD_BASIC_AUTH_USERNAME: admin`.

The deployment manages its own password lifecycle automatically:
1. **Password Generator**: An External Secrets `Password` generator (`hermes-agent-password`) creates a random,
   high-entropy 32-character password on initial deployment (`refreshInterval: "0"` to avoid unintended rotations).
2. **Kubernetes Secret**: An `ExternalSecret` creates `hermes-agent-secret` containing the username, URL, and generated password.
3. **1Password Push**: A `PushSecret` automatically synchronizes the credentials to the `homelab` 1Password vault:
   - **Item**: `hermes-agent`
   - **Fields**: `password`, `username`, and `url` (`https://hermes.${SECRET_DOMAIN}`)

No manual creation of the 1Password item or password is required prior to deployment. Once synchronized, the credentials
can be found in 1Password under `hermes-agent` for browser autofill.

## Architecture and Volumes

- **Image and Supervision**: The deployment runs `docker.io/nousresearch/hermes-agent:0.21.6` with `gateway run`.
  The container uses `s6-overlay` for process supervision, managing both the gateway and web dashboard with
  automatic crash recovery and log rotation.
- **Persistent Data**: The `/opt/data` volume is the single source of truth for all Hermes state, including
  configuration, API keys (`.env`), sessions, persistent memory, and installed skills.
- **SQLite Database**: Sessions and memory are kept in `/opt/data/state.db`. The volume uses `storageClass: node-local`
  (ext4 on Talos), which fully supports SQLite's default WAL (Write-Ahead Logging) journal mode.
- **Concurrency**: A single replica uses `strategy: Recreate` because Hermes session stores and SQLite files
  do not support concurrent multi-instance writes.
- **User Identity**: The container drops privileges to the unprivileged `hermes` user (`UID 10000`, `GID 10000`).
  The pod sets `fsGroup: 10000` to maintain proper file permissions on the persistent volume.

## Endpoints

- **Web Dashboard & Desktop App** (port `9119`): Serves the browser dashboard and acts as the remote backend
  for the Hermes Desktop app. Routed at `/`.
- **OpenAI-Compatible API Server** (port `8642`): Exposes standard OpenAI API endpoints (such as `/v1/chat/completions`)
  and the `/health` endpoint used by liveness and readiness probes. Routed at `/v1`.

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
