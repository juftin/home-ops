# Post-merge Verification

Use this checklist after OIDC or Gateway changes merge to `main`.

______________________________________________________________________

## 1. Reconciliation and Resource Presence

```bash
kubectl get gateway -n network envoy-oauth envoy-oauth-internal
kubectl get securitypolicy -n network envoy-oauth-policy envoy-oauth-internal-policy
kubectl get httproute -n default oauth-pages
kubectl get helmrelease -n network cloudflare-dns
```

Expected:

- Gateways exist and are programmed
- SecurityPolicies are present
- `oauth-pages` route exists
- `cloudflare-dns` release is healthy

______________________________________________________________________

## 2. DNS and TLS Sanity

- [ ] OAuth hostnames resolve (`oauth.<domain>`, `oauth-internal.<domain>`)
- [ ] TLS certificate is served for both hosts
- [ ] Gateway labels still include `home-ops.io/cloudflare-dns=true`

```bash
kubectl get gateway -n network envoy-oauth envoy-oauth-internal --show-labels
```

______________________________________________________________________

## 3. End-to-end Behavior

- [ ] Unauthenticated visit redirects to Google login
- [ ] Allowlisted user can access protected app
- [ ] Non-allowlisted user lands on `/denied`
- [ ] Logout lands on `/logged-out`
- [ ] Callback handling is healthy (no nginx 404 at `/oauth2/callback`)
- [ ] Non-OAuth routes on `envoy-external` remain unaffected

______________________________________________________________________

## 4. Failure Follow-up

If any check fails:

1. Use `docs/OIDC-TROUBLESHOOTING.md`
2. Revert problematic commit if needed
3. Re-verify after Flux reconciliation

______________________________________________________________________

## 5. Token Sync Follow-up (Headlamp)

- [ ] `headlamp-admin-token` ExternalSecret reports Ready after rotation
- [ ] Headlamp login accepts only the rotated token within 5 minutes
- [ ] `https://headlamp.<domain>/token-sync/status` returns current sync state
- [ ] `https://headlamp.<domain>/token-sync/sources` returns source fingerprints metadata
- [ ] `https://headlamp.<domain>/token-sync/incidents` returns incident list payload

```bash
kubectl get externalsecret -n observability headlamp-admin-token
kubectl get configmap -n observability headlamp-token-sync-state -o yaml
kubectl get httproute -n observability token-sync-status
```

______________________________________________________________________

## 6. Change Record

Record in PR comment or handoff note:

- What was validated
- Which hostnames/gateways were tested
- Any follow-up actions required
