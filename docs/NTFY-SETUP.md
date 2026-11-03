# ntfy Setup

[ntfy](https://ntfy.sh) is a self-hosted pub-sub push notification service. It runs in Kubernetes at
`https://ntfy.${SECRET_DOMAIN}` behind the public `envoy-external` Gateway, so phone apps, scripts, and
external services can publish and subscribe from anywhere. Google SSO is intentionally **not** used:
the ntfy Android/iOS apps and HTTP publishers cannot complete a browser OIDC flow. Instead, ntfy's
own access control denies all anonymous access.

## Credentials (1Password)

Users and access tokens are provisioned declaratively from 1Password through the ntfy
[`auth-users`](https://docs.ntfy.sh/config/#users-via-the-config) and
[`auth-tokens`](https://docs.ntfy.sh/config/#tokens-via-the-config) options. Generate the values
with the ntfy CLI (any machine with Docker works, no server required):

```bash
# bcrypt hash for a user's password (prompts for the password)
docker run --rm -it docker.io/binwiederhier/ntfy user hash

# random access token (tk_ prefix, 32 characters)
docker run --rm docker.io/binwiederhier/ntfy token generate
```

Create a **Login** item named `ntfy` in the 1Password **homelab** vault:

- **Title**: `ntfy`
- **Website / URL**: `https://ntfy.${SECRET_DOMAIN}`
- **Username** / **Password**: Your ntfy login (for autofill; the server only reads the fields below)
- **NTFY_AUTH_USERS**: Comma-separated `<username>:<bcrypt-hash>:<role>` entries, e.g.
  `admin:$2a$10$...:admin`. Roles are `admin` (all topics) or `user` (no access unless granted).
- **NTFY_AUTH_TOKENS**: Comma-separated `<username>:<token>[:<label>]` entries, e.g.
  `admin:tk_...:automation`. Each username must exist in `NTFY_AUTH_USERS`.

External Secrets synchronizes both fields into `ntfy-secret` in the `default` namespace, which the
container loads as environment variables. Reloader restarts the pod when either field changes.
Provisioned users and tokens are recreated on every start; removing an entry from 1Password
deletes it from ntfy on the next restart.

To grant a `user`-role account access to specific topics, add an `NTFY_AUTH_ACCESS` field
(`<username>:<topic-pattern>:<rw|ro|wo|deny>` entries) to the 1Password item and to
[externalsecret.yaml](../kubernetes/apps/default/ntfy/app/externalsecret.yaml).

## Configuration

ntfy is configured entirely through `NTFY_*` environment variables in
[values.yaml](../kubernetes/apps/default/ntfy/app/values.yaml):

| Setting               | Value                       | Purpose                                                                    |
| --------------------- | --------------------------- | -------------------------------------------------------------------------- |
| `auth-default-access` | `deny-all`                  | Anonymous clients cannot publish or subscribe                              |
| `require-login`       | `true`                      | The web app requires a login                                               |
| `enable-signup`       | `false`                     | No self-service account creation                                           |
| `behind-proxy`        | `true`                      | Rate limiting uses `X-Forwarded-For`, ignoring pod-network proxy hops      |
| `cache-duration`      | `24h`                       | Messages are kept for clients that reconnect with `since=` / `poll=1`      |
| `attachment-*`        | 2G total, 15M per file, 24h | Attachments stored on the persistent volume                                |
| `upstream-base-url`   | `https://ntfy.sh`           | Forwards poll requests (message IDs only) for iOS instant notifications    |
| `metrics-listen-http` | `:9090`                     | Prometheus metrics on a dedicated, unrouted port scraped by ServiceMonitor |

## Architecture and Volumes

- **Image**: `docker.io/binwiederhier/ntfy` running `ntfy serve` on port `8080` as non-root UID/GID `1000`
  with a read-only root filesystem and all capabilities dropped.
- **Persistent Data**: A 5Gi `node-local` PVC mounted at `/var/lib/ntfy` holds `cache.db` (message cache),
  `user.db` (users, ACLs, tokens), and `attachments/`.
- **Concurrency**: A single replica uses `strategy: Recreate` because the SQLite databases live on a
  ReadWriteOnce volume.
- **Health Probes**: Liveness and readiness use `GET /v1/health`.
- **Streaming**: Subscriptions use long-lived HTTP streams and WebSockets; the shared Envoy
  `BackendTrafficPolicy` disables the request timeout, so connections are not cut off.

## Usage

```bash
# Publish with an access token
curl -H "Authorization: Bearer tk_..." -d "Backup finished" https://ntfy.${SECRET_DOMAIN}/homelab

# Publish with basic auth
curl -u admin:password -d "Backup finished" https://ntfy.${SECRET_DOMAIN}/homelab
```

In-cluster publishers can skip the Gateway and use `http://ntfy.default.svc.cluster.local:8080`.

In the ntfy mobile app, add `https://ntfy.${SECRET_DOMAIN}` as the default server (**Settings → Default
server**) and add your user under **Settings → Manage users** before subscribing to topics.

## Verification

After deployment:

```bash
# Anonymous access is denied (expect 403)
curl -s -o /dev/null -w '%{http_code}\n' -d test https://ntfy.${SECRET_DOMAIN}/test

# Authenticated publish succeeds (expect 200)
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer tk_..." -d test https://ntfy.${SECRET_DOMAIN}/test

# Health endpoint
curl -s https://ntfy.${SECRET_DOMAIN}/v1/health
```
