# OIDC / Pomerium Troubleshooting

This runbook covers common failure modes for Pomerium Google SSO in this repository.

______________________________________________________________________

## Quick Triage

```bash
kubectl get pomerium -n pomerium global -o yaml
kubectl get pods,svc,pvc -n pomerium
kubectl get secret -n pomerium google-idp bootstrap
kubectl get ingress -A --field-selector spec.ingressClassName=pomerium
kubectl logs -n pomerium deployment/pomerium --tail=100
```

If branch testing is active, always finish with:

```bash
task dev:stop
```

______________________________________________________________________

## Symptoms, Checks, and Fixes

## 1) Hostname does not resolve or returns 404

### Check

- `cloudflare-tunnel` (`kubernetes/workloads/network/cloudflare-tunnel/values.yaml`) has an explicit
  entry for the app hostname and `oauth.${SECRET_DOMAIN}` **before** `*.${SECRET_DOMAIN}` pointing
  to `https://pomerium-proxy.pomerium.svc.cluster.local:443` with `originServerName: oauth.${SECRET_DOMAIN}`.
- `cloudflare-dns` wildcard record `*.${SECRET_DOMAIN}` is synced.

### Fix

- Add or fix the hostname entry in `kubernetes/workloads/network/cloudflare-tunnel/values.yaml`
- Run `task lint && task dev:validate`, push, and reconcile

______________________________________________________________________

## 2) Google login loops or callback fails

### Check

- `spec.authenticate.url` in `kubernetes/workloads/network/pomerium/pomerium.yaml` is
  `https://oauth.${SECRET_DOMAIN}`
- `https://oauth.<domain>/oauth2/callback` is registered in Google Cloud Console
- `google-idp` Secret in `pomerium` namespace contains valid `client_id` and `client_secret`
  (not placeholder values)
- `bootstrap` Secret exists in `pomerium` namespace (`kubectl get job -n pomerium pomerium-gen-secrets`)

### Fix

- Run `./scripts/migrate-oauth-to-pomerium.sh` or update `google-idp-secret.sops.yaml` with real
  credentials, re-encrypt, commit, and push

______________________________________________________________________

## 3) User authenticates but receives 403 Forbidden

### Check

- User email (lowercase) is present in the `&admins` or `&users` PPL policy block in
  `kubernetes/workloads/network/pomerium/ingresses.sops.yaml`

```bash
sops --decrypt kubernetes/workloads/network/pomerium/ingresses.sops.yaml | less
```

### Fix

- Add lowercase email to the appropriate PPL `allow.or` email list (keeping `&admins` in `&users`)
- Re-encrypt with `sops --encrypt`, commit, and push

______________________________________________________________________

## 4) Protected app returns 502 / connection timed out from Pomerium

### Check

- Target app has a `CiliumNetworkPolicy` permitting ingress from `pomerium-proxy` pods:
  - `k8s:io.kubernetes.pod.namespace: pomerium`
  - `app.kubernetes.io/name: pomerium`
  - `app.kubernetes.io/component: proxy`
- WebSocket-enabled apps (`paseo`, `herdr`, `hermes-agent`, `openclaw`, `argocd`, `grafana`) have
  `ingress.pomerium.io/allow_websockets: "true"`

### Fix

- Update the app's `networkpolicy.yaml` or `ingresses.sops.yaml` annotation, validate, and reconcile

______________________________________________________________________

## 5) Emergency Session Invalidation

When access must be revoked immediately after allowlist updates:

```bash
kubectl rollout restart deployment -n pomerium pomerium
```
