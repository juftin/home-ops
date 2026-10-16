# Renovate setup

ArgoCD discovers `kubernetes/apps/default/renovate/app` and deploys the official
[Renovate Helm chart](https://github.com/renovatebot/helm-charts/tree/main/charts/renovate).
The CronJob runs every 30 minutes, with overlapping scheduled runs forbidden. It is
initially suspended so credentials and a dry run can be verified before cutover.

The runner discovers repositories owned by `juftin` with the **`renovate-enabled`**
topic, matching the current `juftin/renovate` runner. The GitHub App must also have
access to each repository. `config.js` carries over that runner's configuration:
shared `github>juftin/renovate` presets, Conventional Commits by default, no
onboarding requirement, and repository-local overrides. Set
`RENOVATE_COMMIT_STYLE` to `gitmoji` in `values.yaml` to switch styles.
`GITHUB_REPOSITORY` identifies the preset repository; it does not restrict which
repositories are discovered. Set `RENOVATE_REPOSITORY` to target one repository.

## Credentials

Reuse the GitHub App used by `juftin/renovate`. Install it on the `juftin` account
with access to the repositories to manage, including the preset repository.
Use the permissions in the [Renovate GitHub App documentation](https://docs.renovatebot.com/modules/platform/github/#running-as-a-github-app).

Create an item named **`renovate`** in the **homelab** 1Password vault:

| Field                 | Value                                                      |
| --------------------- | ---------------------------------------------------------- |
| `APP_ID`              | Numeric GitHub App ID from its settings page               |
| `APP_INSTALLATION_ID` | Numeric installation ID from the installation settings URL |
| `APP_PRIVATE_KEY`     | Complete PEM private key, preserving line breaks           |

The ExternalSecret creates `default/renovate-secret`. Credentials are mounted
read-only; the startup script signs a short-lived JWT and requests a fresh
installation token before every run. The private key is not exported to Renovate's
environment. Jobs stop after 55 minutes, before the one-hour installation token
expires. Larger repository sets may need separate jobs or a token refresh design.

The full Renovate image includes package-manager tools. A 5 GiB `node-local` PVC
persists `/tmp/renovate` across runs; UID 12021 and group 0 match the container
image. The cache can be rebuilt if lost. No Service, ingress, or Kubernetes API
permissions are needed.

## Verify and cut over

1. Merge the suspended deployment and wait for ArgoCD to reconcile it. Verify
   `kubectl get externalsecret renovate -n default` reports `SecretSynced` and
   `kubectl get pvc renovate-cache -n default` exists. With node-local storage,
   the claim may remain Pending until the first job is scheduled.

2. Create a dry-run Job from the suspended CronJob. Creating it through a manifest
   allows the environment to be set before any pod starts:

   ```bash
   kubectl create job renovate-dry-run -n default --from=cronjob/renovate --dry-run=client -o yaml \
     | yq '.spec.template.spec.containers[0].env += [{"name": "RENOVATE_DRY_RUN", "value": "full"}]' \
     | kubectl create -f -
   kubectl logs -n default -f job/renovate-dry-run
   kubectl wait -n default --for=condition=complete job/renovate-dry-run --timeout=3300s
   ```

3. Check the logs for successful authentication, discovery of the intended
   repositories, and successful preset resolution. A dry run does not create PRs.
   Delete the completed test with `kubectl delete job renovate-dry-run -n default`.

4. Disable the `renovate.yaml` workflow in **`juftin/renovate`** and the older
   repository-only workflow in **`juftin/home-ops`**, then wait for active runs to
   finish. This PR leaves both workflows intact during setup:

   ```bash
   gh workflow disable renovate.yaml --repo juftin/renovate
   gh workflow disable renovate.yaml --repo juftin/home-ops
   ```

5. Add the `renovate-enabled` topic to `juftin/home-ops` (and other desired
   repositories) if missing. This is required before retiring its repository-only
   workflow:

   ```bash
   gh repo edit juftin/home-ops --add-topic renovate-enabled
   ```

6. Change `cronjob.suspend` to `false` in `values.yaml`, run `task lint` and
   `task dev:validate:ci`, and commit the change for ArgoCD. The CronJob then runs
   on its schedule. Manual Jobs bypass the CronJob's concurrency policy, so avoid
   launching them while another Renovate run is active.

For rollback, suspend the CronJob in Git, let any active Job finish (suspending
does not stop existing Jobs), and re-enable the previous workflows. CI validation
and unrelated GitHub Actions remain in place throughout the migration.
