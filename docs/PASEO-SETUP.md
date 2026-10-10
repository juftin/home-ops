# Paseo Setup

Paseo runs its daemon and bundled web UI in Kubernetes at `https://paseo.${SECRET_DOMAIN}`.
Google SSO restricts browser access to the admin group, and Paseo requires its own password for
API and WebSocket access. Agents run inside the pod and work on repositories in `/workspace`.
This deployment does not expose a daemon running on your laptop.

## Password

Create a **Login** item named `paseo` in the 1Password **homelab** vault. Set its URL to your
Paseo hostname and add a password field named `PASEO_PASSWORD` containing a strong, nonempty
password. External Secrets copies that field into `paseo-secret`. The pod cannot start until
the Secret exists. Reloader restarts the pod when the password changes.

## Provider Setup

The [official image](https://paseo.sh/docs/docker) includes Paseo and Git, but no agent CLIs.
An init container installs Codex (`@openai/codex`) and Antigravity (`agy`) into
`/home/paseo/.local` before the daemon starts. Every pod start attempts to upgrade both to the
latest release. If an upgrade fails, a working installed version is reused; a failed first
installation prevents startup. Both CLIs must pass their version checks before Paseo starts.
The home PVC and `/home/paseo/.local/bin` in `PATH` keep the tools available across pod recreation.

Check installation logs and versions:

```bash
kubectl logs -n default deployment/paseo -c install-agents
kubectl exec -n default deployment/paseo -c app -- codex --version
kubectl exec -n default deployment/paseo -c app -- agy --version
```

Authenticate each provider once inside the running pod as the non-root `paseo` user:

```bash
kubectl exec -it -n default deployment/paseo -c app -- codex login --device-auth
kubectl exec -it -n default deployment/paseo -c app -- agy
```

For Codex, enable device-code login in your ChatGPT security settings if needed, then open the
printed URL and enter the code. See [Codex authentication](https://developers.openai.com/codex/auth/).
For Antigravity, follow its sign-in prompts; see
[installation and auth](https://www.antigravity.google/docs/cli/install/).
The persistent home includes Codex's `.codex` and Antigravity's `.gemini` configuration.
Antigravity may require an accessible Linux keyring for Google sign-in; see Google's
[CLI troubleshooting](https://www.antigravity.google/docs/cli/troubleshooting/).
Pick Codex or Antigravity in Paseo after signing in; neither requires an extra Paseo plugin.
Antigravity supports only Full access in Paseo, with tool calls running without permission prompts.
See [supported providers](https://paseo.sh/docs/supported-providers#antigravity).

Restart the deployment to retry upgrades. Install and authenticate the GitHub CLI inside the pod
if you need Paseo's PR features.

Clone repositories into `/workspace`, then select them in Paseo. The home volume is 5 GiB and
the workspace volume is 20 GiB, both using `node-local` storage. Back these volumes up: they
are tied to a node and are not replicated. Provider tools and repositories are separate from
your laptop's development environment.

## PVC Sync Errors

An immutable `spec.volumeName` error on `paseo-home` or `paseo-workspace` can occur when ArgoCD
replaces a bound PVC with a manifest that omits its Kubernetes-assigned volume name.
The ApplicationSet uses `ServerSideApply=true` without `Replace=true` to preserve those bindings.
See [ArgoCD sync options](https://argo-cd.readthedocs.io/en/latest/user-guide/sync-options/#server-side-apply).
After merging this configuration, sync `home-ops-root` first, confirm the generated `paseo`
Application's sync options contain `ServerSideApply=true` without `Replace=true`, then retry
the Paseo sync. The existing PVCs and their data are retained.

## Validation and Branch Test

```bash
task lint
task dev:validate
task dev:start
kubectl get externalsecret paseo -n default
kubectl get pvc -n default
kubectl rollout status deployment/paseo -n default
kubectl get httproute paseo -n default
```

Open the Paseo hostname, complete Google login, and supply the daemon password when prompted.
Verify the UI connects and can stream a provider session over WebSocket. Check `/denied` and
`/logged-out` on the same hostname. Always finish branch testing with `task dev:stop`, including
when a check fails.

The Cloudflare Tunnel has an explicit Paseo rule before the public wildcard rule. The HTTPRoute
attaches only to `envoy-oauth-admin`; no additional Google OAuth redirect URI is needed because
the existing admin gateway handles the callback. Relay access is disabled, so native or CLI
clients must also handle gateway authentication to connect through this hostname.
