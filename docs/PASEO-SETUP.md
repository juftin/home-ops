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

The [official image](https://github.com/getpaseo/paseo/blob/main/docs/docker.md) includes Paseo
and Git, but no agent CLIs. Install your chosen providers into the persistent home volume:

```bash
kubectl exec -it -n default deployment/paseo -- bash
npm install --global --prefix /home/paseo/.local <provider-package>
```

Replace `<provider-package>` with the npm package for your provider from the
[Paseo provider documentation](https://paseo.sh/docs/providers). The deployment includes
`/home/paseo/.local/bin` in `PATH`, so installed tools survive pod recreation. Complete the
provider's login from this shell; credentials under `/home/paseo` also persist. Install and
authenticate the GitHub CLI here if you need Paseo's PR features. For a reproducible toolchain,
build a child image with your selected CLIs and update the deployment's image reference.

Clone repositories into `/workspace`, then select them in Paseo. The home volume is 5 GiB and
the workspace volume is 20 GiB, both using `node-local` storage. Back these volumes up: they
are tied to a node and are not replicated. Provider tools and repositories are separate from
your laptop's development environment.

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
