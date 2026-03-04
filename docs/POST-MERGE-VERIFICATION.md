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

- [ ] Unauthenticated visit redirects to Authentik login (or legacy provider when mode=legacy)
- [ ] Allowlisted user can access protected app
- [ ] Non-allowlisted user lands on `/denied`
- [ ] Logout lands on `/logged-out`
- [ ] Callback handling is healthy (no nginx 404 at `/oauth2/callback`)
- [ ] Non-OAuth routes on `envoy-external` remain unaffected

Capture at least one allow and one deny outcome with:

- timestamp
- user identity
- protected route
- decision outcome
- denial reason (deny only)

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

## 6. SC-003 Measurement Method

For at least 20 auth-related investigations, track time-to-evidence from incident start to when
operator can identify user + route + outcome + denial reason (if denied). Success target:

- `>=95%` of investigations complete within 10 minutes.

Evidence can be captured in PR notes or incident logs with timestamps and links to query output.
