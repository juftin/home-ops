# AGENTS.md

This is the [juftin/home-ops](https://github.com/juftin/home-ops) repository — a GitOps-driven
Kubernetes homelab on bare metal. Flux continuously reconciles `kubernetes/` from `main`. Talos
Linux is the OS. Secrets are SOPS-encrypted with age. Dependencies are updated by Renovate.

@README.md
@docs/ARCHITECTURE.md
@docs/TASKS.md

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

## Branch Testing Workflow

Always work in a git worktree to keep the main checkout on `main` and isolate feature branches:

```bash
# Create a worktree for the feature branch (sibling of the main checkout)
git worktree add ../home-ops-my-change -b feature/my-change
cd ../home-ops-my-change

# Symlink gitignored files required by dev tasks (Taskfile resolves these from ROOT_DIR)
ln -s ../home-ops/age.key age.key
ln -s ../home-ops/kubeconfig kubeconfig

# edit kubernetes/ manifests
task lint             # auto-fix formatting
task dev:validate     # validate offline
task dev:start        # push branch, suspend flux-instance HelmRelease, patch GitRepository, reconcile
task dev:sync         # push additional commits and reconcile
task dev:stop         # ALWAYS run this — restores flux-instance and points cluster back at main

# Clean up the worktree when done (must be run from outside the worktree)
cd ../home-ops
git worktree remove ../home-ops-my-change
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
3. Use `task dev:start` / `task dev:sync` to test on the live cluster
4. Update **`README.md`** — add the app to the `## Apps` or `## Components` section
5. Update **`docs/ARCHITECTURE.md`** — add the app to the namespaces table and any relevant layer description

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
- **`task lint` always fails on `main`** — the `no-commit-to-branch` hook is expected to fail on
  `main`. All other hooks must pass.
- **`yamlfmt` reformats indentation and multiline strings** — do not manually fight its style;
  always let `task lint` normalize files before committing.
- **Worktrees share the `.git` directory but not gitignored files** — `age.key` and `kubeconfig`
  exist only in the main working tree. Symlink them into the worktree before running `dev:` tasks —
  the Taskfile resolves these from `ROOT_DIR` so env var overrides won't work:
  `ln -s ../home-ops/age.key age.key && ln -s ../home-ops/kubeconfig kubeconfig`.

## Resources

- [onedr0p/home-ops](https://github.com/onedr0p/home-ops) — reference app implementations
- [kubesearch.dev](https://kubesearch.dev/) — community Kubernetes app configs
