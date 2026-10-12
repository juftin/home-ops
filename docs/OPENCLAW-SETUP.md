# OpenClaw Setup

[OpenClaw](https://github.com/openclaw/openclaw) runs at `https://openclaw.${SECRET_DOMAIN}` behind
admin Google SSO. The gateway and Control UI share port 18789. OpenClaw's own token authentication
and device pairing remain enabled.

## Gateway Token (1Password)

Before syncing the app, create a **Login** item named `openclaw` in the **homelab** vault:

- **Title**: `openclaw`
- **Website / URL**: `https://openclaw.${SECRET_DOMAIN}`
- **Password**: Generate a strong random gateway token (at least 32 random bytes).

External Secrets synchronizes the password to `openclaw-secret` as `OPENCLAW_GATEWAY_TOKEN`.
Reloader restarts the gateway when this Secret changes. The pod cannot start until the item exists
and External Secrets has synchronized it. No token is stored in Git or in the seeded config.

## Provider Setup and Browser Pairing

After ArgoCD deploys the app, configure your model provider and optional messaging channels:

```bash
kubectl exec -it -n default deployment/openclaw -c app -- openclaw configure
```

Keep gateway mode `local`, bind `lan`, token authentication, and the configured HTTPS origin.
Provider credentials and configuration are stored on the persistent volume; do not copy them into Git.

Open the public URL, complete Google SSO, and enter the 1Password gateway token in the Control UI's
connection settings. If the browser requests pairing, inspect and approve its specific request:

```bash
kubectl exec -n default deployment/openclaw -c app -- openclaw devices list
kubectl exec -n default deployment/openclaw -c app -- openclaw devices approve <request-id>
```

Do not disable device authentication to bypass pairing. See the official
[Control UI guide](https://docs.openclaw.ai/web/control-ui) and
[Docker deployment guide](https://docs.openclaw.ai/install/docker).

## Storage and Runtime

- The official image is pinned to `ghcr.io/openclaw/openclaw:2026.10.1`.
- One replica uses `Recreate` and a 10 GiB `node-local` PVC mounted at `/home/node`.
  This persists `.openclaw` state, workspace files, and `.config/openclaw` provider credentials.
- The container runs as UID/GID 1000, with no Kubernetes service account token or elevated privileges.
- An init container copies the ConfigMap seed into `.openclaw/openclaw.json` only when that file is absent.
  Subsequent ConfigMap edits do not overwrite the live configuration: use `openclaw configure` or edit the
  persisted configuration intentionally. Back up the volume before upgrades; node-local storage is tied to its node.
- The seed allows only the public HTTPS browser origin and trusts forwarded headers from the cluster pod
  network (`10.42.0.0/16`). SSO is handled by the existing admin Gateway; it does not replace the gateway token.
- Startup and readiness probes use `/startupz` for traffic admission; liveness uses `/healthz`.
  `/readyz` also considers channel health, so a messaging-provider outage does not remove the Control UI backend.
- Docker sandboxing and a managed Chromium browser are not provisioned. Talos has no Docker daemon;
  agent tools execute inside this pod. Configure provider access before expecting chat responses.

## Validation and Branch Testing

```bash
task lint
task dev:validate
task dev:start
kubectl get externalsecret -n default openclaw
kubectl rollout status -n default deployment/openclaw
kubectl get httproute -n default openclaw
# Verify SSO, token authentication, pairing, and a provider-backed chat in the browser.
task dev:stop
```

Always run `task dev:stop` after branch testing, including when a check fails.
