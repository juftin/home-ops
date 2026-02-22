# OIDC Troubleshooting

This runbook covers common failure modes for Envoy Gateway OIDC in this repository.

______________________________________________________________________

## Quick Triage

```bash
kubectl get gateway -n network envoy-oauth envoy-oauth-internal --show-labels
kubectl get securitypolicy -n network envoy-oauth-policy envoy-oauth-internal-policy
kubectl get secret -n network google-oauth-client-secret
kubectl get httproute -n default oauth-pages
kubectl get helmrelease -n network cloudflare-dns
```

If branch testing is active, always finish with:

```bash
task dev:stop
```

______________________________________________________________________

## Symptoms, Checks, and Fixes

## 1) Hostname does not resolve

### Check

```bash
kubectl get gateway -n network envoy-oauth envoy-oauth-internal --show-labels
kubectl get helmrelease -n network cloudflare-dns -o yaml | grep gateway-label-filter
```

### Expected

- OAuth Gateways include `home-ops.io/cloudflare-dns=true`
- `cloudflare-dns` includes `--gateway-label-filter=home-ops.io/cloudflare-dns=true`

### Fix

- Add missing label(s) to Gateway metadata in
  `kubernetes/apps/network/envoy-gateway/app/envoy.yaml`
- Run `task lint && task dev:validate`, push, and reconcile

______________________________________________________________________

## 2) Google login loops or callback fails

### Check

- `spec.oidc.redirectURL` in policy matches the Gateway hostname exactly
- Redirect URI is registered in Google OAuth client

Primary policy file:

- `kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml`

Secondary policy file:

- `kubernetes/apps/network/envoy-gateway/app/oauth-policy-internal.sops.yaml`

### Fix

- Correct redirect URL/host mismatch
- Re-encrypt SOPS file if edited in plaintext
- Push and reconcile

______________________________________________________________________

## 3) User authenticates but receives denied page

### Check

- User email is present (lowercase) in policy allowlist
- `email_verified` claim requirement is present and true

```bash
sops --decrypt kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml | less
```

### Fix

- Add lowercase email to `authorization.rules[].principal.jwt.claims[name=email].values[]`
- Keep `defaultAction: Deny`
- Re-encrypt, commit, push

______________________________________________________________________

## 4) `/denied` or `/logged-out` returns 404

### Check

```bash
kubectl get httproute -n default oauth-pages -o yaml
```

### Expected

- `parentRefs` include both `envoy-oauth` and `envoy-oauth-internal`
- route matches include exact `/denied` and `/logged-out`

### Fix

- Update `kubernetes/apps/default/oauth-pages/app/httproute.yaml`
- Validate and reconcile

______________________________________________________________________

## 5) OAuth Gateway not becoming ready

### Check

```bash
kubectl get gateway -n network envoy-oauth envoy-oauth-internal -o wide
kubectl get secret -n network <secret-domain-production-tls-secret>
```

### Expected

- Gateway has programmed listeners
- TLS secret exists in `network`
- LB IP is available and unique

### Fix

- Correct IP collisions, TLS secret reference, or listener config in `envoy.yaml`

______________________________________________________________________

## Emergency Session Invalidation

When access must be revoked immediately after allowlist updates:

```bash
kubectl rollout restart deployment -n network -l app.kubernetes.io/name=envoy-gateway
```

This forces re-authentication instead of waiting for existing session expiry.
