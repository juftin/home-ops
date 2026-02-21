# Tasks

This project uses [Task](https://taskfile.dev/) as its task runner. Tasks are defined in
`Taskfile.yaml` (root) and `.taskfiles/` (namespaced sub-taskfiles).

Run `task` (or `task default`) to list all available tasks.

______________________________________________________________________

## Top-level Tasks

These tasks are defined directly in `Taskfile.yaml`.

| Task             | Description                                                                            |
| ---------------- | -------------------------------------------------------------------------------------- |
| `task init`      | Initialize configuration files (age key, deploy key, push token, sample configs)       |
| `task configure` | Render and validate all configuration files from `cluster.yaml` / `nodes.yaml`         |
| `task lint`      | Run all pre-commit hooks against every file in the repo                                |
| `task reconcile` | Force Flux to pull in changes from Git immediately                                     |
| `task encrypt`   | Encrypt sensitive local files (cluster.yaml, kubeconfig, etc.) with SOPS to `secrets/` |
| `task decrypt`   | Decrypt files from `secrets/` back to their original paths                             |

______________________________________________________________________

## `bootstrap:` — Cluster Bootstrap

Defined in `.taskfiles/bootstrap/Taskfile.yaml`. Run once when standing up a new cluster.

| Task                   | Description                                                                                                                                   |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `task bootstrap:talos` | Full Talos cluster bootstrap: generates secrets, renders configs, applies machine configs to nodes, bootstraps etcd, and downloads kubeconfig |
| `task bootstrap:apps`  | Runs `scripts/bootstrap-apps.sh` to install core apps (Cilium → CoreDNS → cert-manager → Flux) via Helmfile                                   |

**`bootstrap:talos` steps in order:**

1. Generate cluster secrets (`talsecret.sops.yaml`) if not already present
2. Render node configs via `talhelper genconfig`
3. Apply configs to nodes with `--insecure` (pre-PKI)
4. Bootstrap etcd (retries until ready)
5. Download `kubeconfig` to the repo root

**Prerequisites:** `.sops.yaml`, `age.key`, `talos/talconfig.yaml`, `talhelper`, `talosctl`, `sops`

______________________________________________________________________

## `talos:` — Talos Node Operations

Defined in `.taskfiles/talos/Taskfile.yaml`. Used for day-2 operations on running nodes.

| Task                              | Description                                                                                         |
| --------------------------------- | --------------------------------------------------------------------------------------------------- |
| `task talos:generate-config`      | Re-render Talos node configs from `talconfig.yaml` via `talhelper genconfig`                        |
| `task talos:apply-node IP=<ip>`   | Apply updated Talos config to a single node. Mode defaults to `auto` (can pass `MODE=reboot`, etc.) |
| `task talos:upgrade-node IP=<ip>` | Upgrade Talos on a single node to the version defined in `talenv.yaml`                              |
| `task talos:upgrade-k8s`          | Upgrade Kubernetes to the version defined in `talenv.yaml`                                          |
| `task talos:reset`                | ⚠️ Resets all nodes back to maintenance mode (destroys the cluster)                                 |

**Variable reference:**

| Variable | Description                                                    |
| -------- | -------------------------------------------------------------- |
| `IP`     | Node IP address (required for `apply-node` and `upgrade-node`) |
| `MODE`   | Talos apply mode for `apply-node` — defaults to `auto`         |

______________________________________________________________________

## `template:` — Template Lifecycle

Defined in `.taskfiles/template/Taskfile.yaml`. Manages the initial config templating workflow
and provides utilities inherited from the upstream
[cluster-template](https://github.com/onedr0p/cluster-template).

| Task                  | Description                                                                                                                      |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `task template:debug` | Print common cluster resources (`nodes`, `pods`, `helmreleases`, `kustomizations`, etc.) across all namespaces                   |
| `task template:tidy`  | Archive template-related files (templates/, makejinja.toml, cluster.yaml, etc.) to `.private/` and clean up template scaffolding |
| `task template:reset` | ⚠️ Remove all rendered directories (`bootstrap/`, `kubernetes/`, `talos/`, `.sops.yaml`)                                         |

> `template:tidy` and `template:reset` are primarily used in the upstream template's CI/CD
> (`e2e.yaml`) to clean up after end-to-end tests. Use with caution on a live cluster.

______________________________________________________________________

## `dev:` — Local Development / Branch Testing

Defined in `.taskfiles/dev/Taskfile.yaml`. Enables testing changes against the live cluster
**without pushing to `main`** by temporarily redirecting Flux to watch the current git branch.

| Task                | Description                                                                                                                                              |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `task dev:validate` | Run `flux-local test` locally via Docker — validates all Helm renders and Kustomization builds with no cluster required                                  |
| `task dev:start`    | Push current branch, suspend the `flux-instance` HelmRelease, patch the `flux-system` GitRepository to watch the current branch, and trigger a reconcile |
| `task dev:sync`     | Push new commits on the current branch and trigger Flux to reconcile them                                                                                |
| `task dev:stop`     | Restore the GitRepository to `refs/heads/main`, resume the `flux-instance` HelmRelease, and trigger a reconcile                                          |

**Typical workflow:**

```bash
git checkout -b feature/my-change
# edit kubernetes/ manifests ...
task dev:start      # redirect Flux at this branch
# iterate:
task dev:sync       # push + reconcile after each change
# done:
task dev:stop       # restore Flux to main
```

> `dev:start` suspends the `flux-instance` HelmRelease so the flux-operator does not fight the
> GitRepository patch. `dev:stop` resumes it and restores everything to the production state.
> Neither `dev:start` nor `dev:sync` can be run on `main`.

______________________________________________________________________

## Internal / Sub-tasks

The following tasks are called internally by `configure` and `init` and are not intended to be
run directly:

| Internal Task                | Called By   | Description                                                                     |
| ---------------------------- | ----------- | ------------------------------------------------------------------------------- |
| `validate-schemas`           | `configure` | Validates `cluster.yaml` and `nodes.yaml` against CUE schemas                   |
| `render-configs`             | `configure` | Runs `makejinja` to render templates into actual YAML manifests                 |
| `encrypt-secrets`            | `configure` | SOPS-encrypts all `*.sops.*` files in `bootstrap/`, `kubernetes/`, and `talos/` |
| `validate-kubernetes-config` | `configure` | Runs `kubeconform` against the rendered Kubernetes manifests                    |
| `validate-talos-config`      | `configure` | Validates `talconfig.yaml` with `talhelper validate talconfig`                  |
| `generate-age-key`           | `init`      | Generates `age.key` if not present                                              |
| `generate-deploy-key`        | `init`      | Generates `github-deploy.key` (ed25519 SSH key) if not present                  |
| `generate-push-token`        | `init`      | Generates `github-push-token.txt` if not present                                |

______________________________________________________________________

## Environment Variables

The following environment variables are set automatically by `Taskfile.yaml` and `.mise.toml`:

| Variable            | Value                                         | Description                                            |
| ------------------- | --------------------------------------------- | ------------------------------------------------------ |
| `KUBECONFIG`        | `<repo-root>/kubeconfig`                      | Kubernetes config file used by `kubectl` and `flux`    |
| `SOPS_AGE_KEY_FILE` | `<repo-root>/age.key`                         | Age private key used by SOPS for encryption/decryption |
| `TALOSCONFIG`       | `<repo-root>/talos/clusterconfig/talosconfig` | Talos client config used by `talosctl`                 |
