# Post-merge Verification

Use this checklist after OIDC, Gateway, or ArgoCD rollout changes merge to `main`.

______________________________________________________________________

## 1. Reconciliation and Resource Presence

```bash
kubectl get gateway -n network envoy-oauth-admin envoy-oauth-users envoy-oauth-internal
kubectl get securitypolicy -n network envoy-oauth-admin-policy envoy-oauth-users-policy envoy-oauth-internal-policy
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

- [ ] OAuth hostnames resolve (`oauth.<domain>`, `oauth-users.<domain>`, `oauth-internal.<domain>`)
- [ ] TLS certificate is served for all OAuth hosts
- [ ] Gateway labels still include `home-ops.io/cloudflare-dns=true`

```bash
kubectl get gateway -n network envoy-oauth-admin envoy-oauth-users envoy-oauth-internal --show-labels
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

## 5. Change Record

Record in PR comment or handoff note:

- What was validated
- Which hostnames/gateways were tested
- Any follow-up actions required

______________________________________________________________________

## 6. ArgoCD Post-cutover Operations

Use this section when a merge affects ArgoCD bootstrap, migration, rollback, or RBAC:

```bash
task dev:argocd:render
task dev:argocd:verify-health
task dev:argocd:validate-rbac
kubectl get applications -n argocd
```

Expected:

- ArgoCD manifests render cleanly.
- ArgoCD applications are healthy/synced with no critical drift.
- RBAC policy object exists with admin and read-only mappings.

When branch-testing with `task dev:start`, `flux-system-flux-instance` may remain
`OutOfSync`/`Suspended` until `task dev:stop` restores normal Flux reconciliation.
