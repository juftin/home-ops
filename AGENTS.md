# AGENTS.md

This is the [juftin/home-ops](https://github.com/juftin/home-ops) repository — a GitOps-driven
Kubernetes homelab on bare metal. Flux continuously reconciles `kubernetes/` from `main`. Talos
Linux is the OS. Secrets are SOPS-encrypted with age. Dependencies are updated by Renovate.

@README.md
@docs/ARCHITECTURE.md
@docs/TASKS.md
@docs/GOOGLE-OAUTH-SETUP.md
@docs/OIDC-TROUBLESHOOTING.md
@docs/GATEWAY-ONBOARDING-CHECKLIST.md
@docs/SECURITYPOLICY-CHANGE-PLAYBOOK.md
@docs/POST-MERGE-VERIFICATION.md

## Environment Setup

Run once after cloning:

```bash
mise install          # install all pinned tools (.mise.toml)
pre-commit install    # install git hooks
```

Gitignored files that must exist locally:

| File                              | How to get it                          |
| --------------------------------- | -------------------------------------- |
| `age.key`                         | Age private key — run `task decrypt`   |
| `kubeconfig`                      | Kubernetes config — run `task decrypt` |
| `talos/clusterconfig/talosconfig` | Run `task talos:generate-config`       |

## Validation — Always Run Before Finishing

Run these in order before considering any task complete:

```bash
task lint           # auto-fixes YAML/Markdown formatting; run until clean (second run always passes)
task dev:validate   # renders all Flux HelmReleases and Kustomizations — no cluster required
```

## Development Rules

- **Never commit directly to `main`** — pre-commit blocks it; always use a feature branch.
- **Always use a git worktree for feature work** — never `git checkout -b` in the main working tree;
  create a worktree so the main tree stays on `main` and work is fully isolated.
- **Never store plaintext secrets** — all `*.sops.yaml` files must be SOPS-encrypted. `task configure`
  encrypts them automatically. Never leave decrypted secrets uncommitted.
- **Do not use `kubectl apply` to test changes** — Flux has `prune: true` and will overwrite direct
  applies at the next reconcile. Use the branch testing workflow instead.
- **Always run `task lint` before committing** — `yamlfmt` and `mdformat` auto-fix files in place;
  committing un-formatted files fails CI.
- **Use a single emoji to prefix commit messages** — one emoji followed by a short description,
  matching the repo's commit style. Examples: `🤫 external-secrets`, `🔐 sops`, `📝 README`,
  `🤖 AGENTS.md`, `🧹 renovate`. Pick an emoji that reflects the nature of the change.

## Branch Testing Workflow

Always work in a git worktree to keep the main checkout on `main` and isolate feature branches:

```bash
# Create a worktree for the feature branch under ./worktrees/
task dev:worktree:create NAME=home-ops-my-change
cd worktrees/home-ops-my-change

# edit kubernetes/ manifests
task lint             # auto-fix formatting
task dev:validate     # validate offline
task dev:start        # push branch, suspend flux-instance HelmRelease, patch GitRepository, reconcile
task dev:sync         # push additional commits and reconcile
task dev:stop         # ALWAYS run this — restores flux-instance and points cluster back at main

# Clean up the worktree when done (must be run from outside the worktree)
cd ../..
git worktree remove worktrees/home-ops-my-change
```

> Always run `task dev:stop` when done, even if something went wrong. It restores the
> `flux-instance` HelmRelease and resets the cluster to track `main`.

## Adding a New App

All apps live under `kubernetes/apps/<namespace>/<app-name>/`. Exact structure:

```
kubernetes/apps/<namespace>/
├── kustomization.yaml      # add a resources entry pointing at the new ks.yaml
├── namespace.yaml          # Namespace manifest (if new namespace)
└── <app-name>/
    ├── ks.yaml             # Flux Kustomization for this app
    └── app/
        ├── kustomization.yaml
        ├── ocirepository.yaml  # OCI Helm chart source
        ├── helmrelease.yaml    # HelmRelease with chart values
        ├── externalsecret.yaml # ExternalSecret from 1Password (if needed, see below)
        └── *.sops.yaml         # SOPS-encrypted secrets (if needed)
```

Use `kubernetes/apps/default/echo/` as a working reference. After adding files:

1. Add a `resources:` entry in the parent namespace `kustomization.yaml` for the new `ks.yaml`
2. Run `task lint` then `task dev:validate`
3. Use `task dev:start` / `task dev:sync` to test on the live cluster; run `task dev:stop` when
   done — **always**, even if something went wrong
4. Update **`README.md`** — add the app to the `## Apps` or `## Components` section
5. Update **`docs/ARCHITECTURE.md`** — add the app to the namespaces table and any relevant layer description

**If the app is OAuth-protected**:

1. Add an explicit hostname entry in
   `kubernetes/apps/network/cloudflare-tunnel/app/helmrelease.yaml` **before** the wildcard
   `*.${SECRET_DOMAIN}` rule. Route by group:
   - admins: `https://envoy-oauth-admin.<namespace>.svc.cluster.local:443` with `originServerName: oauth.${SECRET_DOMAIN}`
   - users: `https://envoy-oauth-users.<namespace>.svc.cluster.local:443` with `originServerName: oauth-users.${SECRET_DOMAIN}`
2. Add the app hostname to
   `kubernetes/apps/default/oauth-pages/app/httproute.yaml` so `/denied` and `/logged-out` work on
   that host.
3. Keep `/oauth2/callback` route handling on `oauth-pages` and do not broaden
   `oauth-pages-public` to allow callback.

**For app secrets**: prefer `ExternalSecret` + 1Password over committing a new `.sops.yaml`.
See [`specs/001-external-secrets-1password/quickstart.md`](specs/001-external-secrets-1password/quickstart.md).

## CI — What Runs on Pull Requests

PRs to `main` with changes under `kubernetes/` trigger two jobs:

1. **`flux-local test`** — renders all HelmReleases and Kustomizations; fails on any render error
2. **`flux-local diff`** — diffs changed `helmrelease` and `kustomization` resources vs `main`, posted as a PR comment

Replicate CI locally with `task dev:validate` before opening a PR.

## Gotchas

- **SOPS files are valid YAML with encrypted values** — never `kubectl apply` them directly. Flux
  decrypts them in-cluster via the `sops-age` secret.
- **`task dev:start` suspends `flux-instance` HelmRelease** — the flux-operator manages the
  `flux-system` GitRepository and would immediately reset any branch patch without this suspension.
- **`task dev:stop` must be run before the PR is considered ready** — the cluster tracks the feature
  branch while testing; `dev:stop` resets it to `main`. Run it as soon as live testing is complete,
  not only when explicitly asked.
- **`task lint` always fails on `main`** — the `no-commit-to-branch` hook is expected to fail on
  `main`. All other hooks must pass.
- **`yamlfmt` reformats indentation and multiline strings** — do not manually fight its style;
  always let `task lint` normalize files before committing.
- **Worktrees share the `.git` directory but not gitignored files** — `age.key` and `kubeconfig`
  exist only in the main working tree. Use `task dev:worktree:create` to create the worktree and
  symlink these files correctly before running `dev:` tasks.
- **`components/sops` is the only Kustomize component on `main`** — namespace-level
  `kustomization.yaml` files must use `../../components/sops`. Do not copy namespace kustomizations
  from feature branches that used `../../components/common`; that directory does not exist on `main`.
- **OAuth Gateways must include the Cloudflare DNS label** — `cloudflare-dns` now discovers Gateway
  resources using `--gateway-label-filter=home-ops.io/cloudflare-dns=true`. If the label is missing
  from a Gateway, its DNS records will not be created/updated in Cloudflare.
- **`oauth-pages` requires URL rewrites for friendly paths** — `/denied` and `/logged-out` must be
  rewritten to `/denied.html` and `/logged-out.html` in
  `kubernetes/apps/default/oauth-pages/app/httproute.yaml`; otherwise nginx serves 404.
- **Keep oauth utility pages publicly reachable** — `kubernetes/apps/default/oauth-pages/app/securitypolicy.yaml`
  intentionally sets `authorization.defaultAction: Allow` on the `oauth-pages` HTTPRoute so denied/logout
  pages do not get trapped behind the gateway-level OIDC challenge.
- **Default auth UX is immediate provider redirect** — do not add or keep a public `/login` route unless
  explicitly requested for a temporary test; protected paths should immediately initiate OIDC login.
- **ServiceAccount tokens from `kubectl create token` go stale** — these JWTs embed the SA's
  current UID. If the SA is deleted and recreated (e.g. after branch testing), any stored token
  becomes invalid. Regenerate with:
  `kubectl create token <sa-name> -n <namespace> --duration=8760h`
- **Use `Login` (not `Server`) type for 1Password items tied to a browser URL** — only `Login`,
  `Password`, and `API Credential` item types support the URL field for autofill. `Server` items
  silently ignore `--url`.

## Resources

- [onedr0p/home-ops](https://github.com/onedr0p/home-ops) — reference app implementations
- [kubesearch.dev](https://kubesearch.dev/) — community Kubernetes app configs
