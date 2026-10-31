# Gateway Onboarding Checklist

Use this checklist whenever adding a new Gateway (especially OAuth Gateways).

______________________________________________________________________

## 1. Design Inputs

- [ ] Pick gateway name (`envoy-oauth-admin` or `envoy-oauth-<group>`)
- [ ] Reserve unique LB IP from MetalLB/Cilium IPAM pool
- [ ] Pick DNS hostname under `${SECRET_DOMAIN}`
- [ ] Decide external vs internal DNS target annotation

______________________________________________________________________

## 2. Mandatory Gateway Manifest Requirements

File: `kubernetes/apps/network/envoy-gateway/app/envoy.yaml`

- [ ] `metadata.labels.home-ops.io/cloudflare-dns: "true"` (required for Cloudflare DNS sync)
- [ ] `metadata.labels.home-ops.io/oauth-gateway: "true"` (required for OAuth policy targeting)
- [ ] `metadata.annotations.external-dns.alpha.kubernetes.io/target` set correctly
- [ ] `metadata.annotations.lbipam.cilium.io/ips` set to reserved IP
- [ ] HTTPS listener includes cert ref:
  `${SECRET_DOMAIN/./-}-production-tls` in namespace `network`
- [ ] HTTP listener is present for shared HTTPS redirect route

______________________________________________________________________

## 3. Security Policy and Secret Wiring

Files:

- `kubernetes/apps/network/envoy-gateway/app/oauth-client-secret.sops.yaml`

- `kubernetes/apps/network/envoy-gateway/app/oauth-policy*.sops.yaml`

- `kubernetes/apps/network/envoy-gateway/app/kustomization.yaml`

- [ ] `SecurityPolicy.spec.targetRefs` points to new Gateway

- [ ] Public hardening patch and audience replacements cover the new policy

- [ ] Callback uses the request host over HTTPS; cookies have no `cookieDomain`

- [ ] `jwt.providers` configured for Google issuer/JWKS

- [ ] `authorization.defaultAction: Deny`

- [ ] Verified-email extension covers this Gateway and requires boolean `true`

- [ ] allowlist emails are lowercase

- [ ] SOPS files are encrypted

- [ ] New policy file registered in app `kustomization.yaml`

______________________________________________________________________

## 4. Static UX Route Coverage

File: `kubernetes/apps/default/oauth-pages/app/values.yaml`

- [ ] Add new Gateway to `route.app.parentRefs`
- [ ] Add each protected app hostname explicitly to `route.app.hostnames`
- [ ] Verify `/denied` and `/logged-out` route to `oauth-pages`
- [ ] Verify `/denied` -> `/denied.html` and `/logged-out` -> `/logged-out.html` rewrites exist
- [ ] Keep `/oauth2/callback` as its own route rule (no public allow override)

File: `kubernetes/apps/default/oauth-pages/app/securitypolicy.yaml`

- [ ] `oauth-pages-public` allows only `sectionName: denied` and `sectionName: logged-out`

______________________________________________________________________

## 5. Google OAuth Console

- [ ] Add redirect URI: `https://<app-host>/oauth2/callback`
- [ ] Confirm client ID/secret are current

______________________________________________________________________

## 6. Validation and Branch Test

- [ ] `task lint`
- [ ] `task dev:auth:test`
- [ ] `task dev:validate`
- [ ] Update authentication invariant checks for any new Gateway/group
- [ ] `task dev:start`
- [ ] `kubectl get gateway -n network <gateway-name>`
- [ ] Browser test:
  - [ ] unauthenticated user gets Google redirect
  - [ ] allowlisted user gets access
  - [ ] non-allowlisted user receives HTTP 403; `/denied` remains a public utility page
  - [ ] logout lands on `/logged-out`
- [ ] `task dev:stop` (required)
