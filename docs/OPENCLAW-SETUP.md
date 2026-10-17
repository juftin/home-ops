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

## Antigravity Claude Proxy

[Antigravity Claude Proxy](https://github.com/badrisnarayanan/antigravity-claude-proxy) runs as a
sidecar in the OpenClaw pod. An init container installs the pinned npm release and registers the
`antigravity-proxy` provider in the persisted OpenClaw configuration on each pod start. This provider
is managed by Git; changes to its ConfigMap replace that provider's configuration on restart.
Other providers, gateway settings, channels, and the default model are preserved. OpenClaw's config
CLI performs the update, including for existing JSON5 configurations; writing can remove JSON5 comments.

The proxy listens only on `127.0.0.1:8080` inside the pod. Its API and management dashboard have no
Service, HTTPRoute, or public hostname. The provider's `local-proxy` API key is a placeholder for the
loopback connection, not a credential. Google account tokens and proxy settings remain on the PVC
under `/home/node/.config/antigravity-proxy` and must never be copied into Git.

After deployment, forward the dashboard to your local machine:

```bash
kubectl port-forward -n default deployment/openclaw 8080:8080
```

Open `http://127.0.0.1:8080`, select **Accounts → Add Account**, and use **Manual Authorization**
to link a Google account from your browser. Copy the full callback URL (or its `code` value) from
the browser's address bar into the dashboard, even if the callback page cannot load. Keep the
port-forward running until authorization finishes, then close it. Linking an
account is required before the proxy can serve model requests.

List the registered models and select one when ready:

```bash
kubectl exec -n default deployment/openclaw -c app -- openclaw models list --provider antigravity-proxy
kubectl exec -n default deployment/openclaw -c app -- openclaw models set antigravity-proxy/claude-sonnet-4-6
```

The catalog includes Claude Sonnet 4.6, Sonnet 4.6 Thinking, Opus 4.6 Thinking, Gemini 3.8 Flash,
and Gemini 3.6 Flash High. Model access depends on the linked account. If an existing model allowlist
limits the list, `openclaw models set` adds the selected model to it. Send a chat request through
OpenClaw to verify the linked account and chosen model work together.

Inspect the sidecar without printing account credentials:

```bash
kubectl logs -n default deployment/openclaw -c install-antigravity
kubectl logs -n default deployment/openclaw -c antigravity-proxy
```

## Storage and Runtime

- The official image is pinned to `ghcr.io/openclaw/openclaw:2026.10.1`.
- One replica uses `Recreate` and a 10 GiB `node-local` PVC mounted at `/home/node`.
  This persists `.openclaw` state, workspace files, and `.config/openclaw` provider credentials.
- The container runs as UID/GID 1000, with no Kubernetes service account token or elevated privileges.
- An init container copies the ConfigMap seed into `.openclaw/openclaw.json` only when that file is absent.
  Subsequent ConfigMap edits do not overwrite the live configuration: use `openclaw configure` or edit the
  persisted configuration intentionally. The `antigravity-proxy` provider is updated separately on each start.
  Back up the volume before upgrades; node-local storage is tied to its node.
- The seed allows only the public HTTPS browser origin and trusts forwarded headers from the cluster pod
  network (`10.42.0.0/16`). SSO is handled by the existing admin Gateway; it does not replace the gateway token.
- Startup and readiness probes use `/startupz` for traffic admission; liveness uses `/healthz`.
  `/readyz` also considers channel health, so a messaging-provider outage does not remove the Control UI backend.
- Sidecar probes use an exec HTTP check against its loopback dashboard. They do not request Google
  account quotas, so account setup or an upstream provider outage does not trigger container restarts.
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
