# Quickstart Validation Guide: Pomerium SSO Migration

## Prerequisites

- Local tools installed (`task`, `kustomize`, `helm`, `helmfile`, `sops`, `yq`, `kubeconform`, `pre-commit`)
- For real secret migration and live cluster validation: `age.key` and `kubeconfig` in the repository/worktree root

## 1. Migrate Existing Encrypted OAuth Data (Operator Local Machine)

Run once from a checkout with `age.key` present to copy the existing Google `client_id`, `client_secret`, and `Admins`/`Users` email lists from `origin/main` into the new Pomerium SOPS files:

```bash
./scripts/migrate-oauth-to-pomerium.sh
```

## 2. Offline Validation (CI & Local)

```bash
task lint
task dev:validate:ci
```

With `age.key` present after step 1:

```bash
task dev:validate
```

## 3. Live Cluster Branch Test

```bash
task dev:start
kubectl get pomerium -n pomerium global -o yaml
kubectl get pods,pvc,svc -n pomerium
kubectl get ingress -A -l app.kubernetes.io/part-of=pomerium-sso
```

Verify in browser:

1. Unauthenticated access to `https://paseo.<domain>` redirects to Google login via `https://oauth.<domain>/oauth2/callback`.
2. Admin email accesses `paseo`, `agentsview`, `herdr`, `hermes`, `openclaw`, `argocd`, and `grafana` with single sign-on.
3. Users-only email accesses `grafana` and receives `403` on admin apps.
4. `https://echo.<domain>`, `https://camply.rocks`, and `https://ntfy.camply.rocks` remain publicly accessible without SSO.
5. Finish with `task dev:stop`.
