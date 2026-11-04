# OIDC Troubleshooting

This runbook covers common failure modes for Envoy Gateway OIDC in this repository.

______________________________________________________________________

## Quick Triage

```bash
kubectl get gateway -n network envoy-oauth-admin envoy-oauth-users envoy-oauth-internal --show-labels
kubectl get securitypolicy -n network envoy-oauth-admin-policy envoy-oauth-users-policy envoy-oauth-internal-policy
kubectl get securitypolicy -n default oauth-pages-public -o yaml
kubectl get secret -n network google-oauth-client-secret
kubectl get httproute -n default oauth-pages
kubectl get deployment -n network cloudflare-dns
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
kubectl get gateway -n network envoy-oauth-admin envoy-oauth-users envoy-oauth-internal --show-labels
kubectl get deployment -n network cloudflare-dns -o yaml | rg gateway-label-filter
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

- Rendered `spec.oidc.redirectURL` uses the app request host over HTTPS; Google has that exact app callback registered
- Redirect URI is registered in Google OAuth client
- `oauth-pages` includes the exact `/oauth2/callback` route
- `oauth-pages-public` policy does **not** broadly allow the callback route
- `cloudflare-tunnel` has explicit OAuth host ingress entries before `*.${SECRET_DOMAIN}`:
  - `oauth.${SECRET_DOMAIN}` -> `envoy-oauth-admin`
  - `oauth-users.${SECRET_DOMAIN}` -> `envoy-oauth-users`

Policy files:

- `kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml`
  (contains both `envoy-oauth-admin-policy` for admins and `envoy-oauth-users-policy` for users)
- `kubernetes/apps/network/envoy-gateway/app/oauth-policy-internal.sops.yaml` (internal)

### Fix

- Correct redirect URL/host mismatch
- Ensure callback handling stays on the OIDC flow:
  - `oauth-pages` route rule `callback` matches `/oauth2/callback`
  - `oauth-pages-public` only targets `sectionName: denied` and `sectionName: logged-out`
- Ensure `cloudflare-tunnel` sends OAuth hostnames to the matching OAuth Gateway services with
  explicit hostname rules before the wildcard route
- Re-encrypt SOPS file if edited in plaintext
- Push and reconcile

______________________________________________________________________

## 3) User authenticates but receives HTTP 403

### Check

- User email is present (lowercase) in policy allowlist
- `oauth-verified-email` EnvoyExtensionPolicy is accepted and the verified JWT contains boolean `email_verified: true`

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

- `parentRefs` include `envoy-oauth-admin`, `envoy-oauth-users`, and `envoy-oauth-internal`
  (and `envoy-external` if used)
- `hostnames` explicitly includes the app host; a wildcard alone loses precedence to the app's exact hostname
- route rules include exact `/denied` and `/logged-out`
- rules rewrite to `/denied.html` and `/logged-out.html`
- `oauth-pages-public` allows only `sectionName: denied` and `sectionName: logged-out`

### Fix

- Update `kubernetes/apps/default/oauth-pages/app/values.yaml`
- Confirm `kubernetes/apps/default/oauth-pages/app/securitypolicy.yaml` is section-scoped
- Validate and reconcile

______________________________________________________________________

## 5) OAuth Gateway not becoming ready

### Check

```bash
kubectl get gateway -n network envoy-oauth-admin envoy-oauth-users envoy-oauth-internal -o wide
kubectl get secret -n network <secret-domain-production-tls-secret>
```

### Expected

- Gateway has programmed listeners
- TLS secret exists in `network`
- LB IP is available and unique

### Fix

- Correct IP collisions, TLS secret reference, or listener config in `envoy.yaml`

______________________________________________________________________

## Revocation and Session Invalidation

Use the [policy change playbook](SECURITYPOLICY-CHANGE-PLAYBOOK.md#revocation).
An allowlist change affects subsequent requests after data-plane policy propagation.
Restarting the controller does not invalidate browser sessions; active streams and
cookie-signing-key rotation require separate handling.

For repeated login failures after an upgrade, inspect the **rendered** policy: cookie names must match the JWT cookie extractor, token encryption must be disabled for
this pinned controller's JWT-cookie path, and JWT must verify the OIDC client ID audience.
OAuth cookies must be stripped before app forwarding. Client query parameters and bearer
headers do not bypass browser OIDC.
