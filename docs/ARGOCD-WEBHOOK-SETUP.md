# ArgoCD GitHub Webhooks

GitHub push events refresh existing ArgoCD Applications immediately instead of waiting for Git
polling. ArgoCD's existing automated sync policies still control deployment. ApplicationSet
directory discovery uses a separate webhook server and continues to poll; adding an app directory
may therefore take longer than updating an existing app.

The endpoint is `https://webhooks.<YOUR_DOMAIN>/argocd/api/webhook`. Cloudflare Tunnel's existing
public wildcard sends it to `envoy-external`, which matches only `POST /argocd/api/webhook` and
rewrites the upstream path to `/api/webhook` on `argocd-server:80`. The shared `webhooks` hostname
uses an app-specific `/argocd/` path. The ArgoCD UI stays behind admin Google SSO at
`argocd.<YOUR_DOMAIN>`.

## 1. Store the shared secret

In the **homelab** 1Password vault, create or update the **argocd** item with a password field named
**GITHUB_WEBHOOK_SECRET**. Generate a random value of at least 32 characters in 1Password. Use the
same value for GitHub in step 3; do not commit it or paste it into command history.

The bootstrap chart creates `ExternalSecret/argocd-webhook`, which copies this field into
`argocd-webhook-secret` under `webhook.github.secret`. The Secret has the
`app.kubernetes.io/part-of: argocd` label, and `argocd-secret` contains the reference
`$argocd-webhook-secret:webhook.github.secret`. Helm stores only the reference, not the shared secret.

## 2. Deploy the bootstrap changes

Merge the configuration, then run from the main checkout with its existing local credentials:

```bash
task argocd:bootstrap
task argocd:bootstrap:verify
kubectl wait --for=condition=Ready clustersecretstore/onepassword --timeout=120s
kubectl wait -n argocd --for=condition=Ready externalsecret/argocd-webhook --timeout=120s
kubectl get secret -n argocd argocd-webhook-secret --show-labels
kubectl get httproute -n argocd argocd-webhook -o yaml
```

The route's parent status must show `Accepted=True` and `ResolvedRefs=True`. Check that the
ExternalSecret is Ready before enabling GitHub deliveries. Bootstrap values are managed by
Helmfile, so merging alone or running `task dev:start` does not install this change. Running the
bootstrap task on a feature branch also points `home-ops-root` at that branch; always finish any
branch test with `task dev:stop`.

## 3. Add the GitHub webhook

Open [juftin/home-ops webhook settings](https://github.com/juftin/home-ops/settings/hooks) and choose
**Add webhook**:

| Setting          | Value                                               |
| ---------------- | --------------------------------------------------- |
| Payload URL      | `https://webhooks.<YOUR_DOMAIN>/argocd/api/webhook` |
| Content type     | `application/json`                                  |
| Secret           | The `GITHUB_WEBHOOK_SECRET` value from 1Password    |
| SSL verification | Enable                                              |
| Events           | Just the push event                                 |
| Active           | Checked                                             |

The GitHub account or token needs repository webhook administration access. For GitHub CLI using a
classic OAuth token, the scope is `admin:repo_hook`.

## 4. Verify delivery and reconciliation

Under the webhook's **Recent Deliveries**, check that the initial `ping` receives HTTP 200. Then
push or merge a normal manifest change and check that the `push` delivery also receives HTTP 200.
Confirm that the affected Application refreshes and syncs to the pushed revision:

```bash
kubectl get applications -n argocd
kubectl get application -n argocd <APP_NAME> \
  -o jsonpath='{.status.sync.revision}{"\n"}{.status.reconciledAt}{"\n"}'
```

A successful ping checks connectivity and authentication; the push event checks application
refresh. A push to a different branch does not deploy it to Applications tracking `main`.

| Symptom                      | Check                                                                                                           |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------- |
| DNS or TLS failure           | Cloudflare DNS record for the route hostname, wildcard tunnel rule, and the public Gateway certificate          |
| 302 redirect to Google       | Payload URL must use the `webhooks` hostname                                                                    |
| 404                          | Exact path `/argocd/api/webhook`, POST method, `/api/webhook` upstream rewrite, and HTTPRoute parent conditions |
| Signature validation failure | Matching GitHub and 1Password secrets and a Ready ExternalSecret                                                |
| HTTP 200 but no update       | Delivery event is `push`; Application repository and target branch match the payload                            |

For rotation, update the 1Password field and GitHub webhook secret together, then request a secret
refresh and redeliver any failed push from GitHub:

```bash
kubectl annotate externalsecret -n argocd argocd-webhook \
  force-sync="$(date +%s)" --overwrite
```

ArgoCD reloads the referenced secret automatically. Polling remains enabled as a fallback.

See the upstream [ArgoCD webhook guide](https://argo-cd.readthedocs.io/en/release-3.4/operator-manual/webhook/)
and [GitHub webhook setup guide](https://docs.github.com/en/webhooks/using-webhooks/creating-webhooks).
