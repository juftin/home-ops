# Gateway Onboarding Checklist

Use this checklist whenever adding a new Gateway (especially OAuth Gateways).

______________________________________________________________________

## 1. Design Inputs

- [ ] Pick gateway name (`envoy-oauth` or `envoy-oauth-<group>`)
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

- [ ] `oidc.redirectURL` and `logoutRedirectURL` match new hostname

- [ ] `jwt.providers` configured for Google issuer/JWKS

- [ ] `authorization.defaultAction: Deny`

- [ ] `email_verified=true` claim present

- [ ] allowlist emails are lowercase

- [ ] SOPS files are encrypted

- [ ] New policy file registered in app `kustomization.yaml`

______________________________________________________________________

## 4. Static UX Route Coverage

File: `kubernetes/apps/default/oauth-pages/app/httproute.yaml`

- [ ] Add new Gateway to `parentRefs`
- [ ] Ensure hostnames include new OAuth host if needed
- [ ] Verify `/denied` and `/logged-out` route to `oauth-pages`

______________________________________________________________________

## 5. Google OAuth Console

- [ ] Add redirect URI: `https://<oauth-host>/oauth2/callback`
- [ ] Confirm client ID/secret are current

______________________________________________________________________

## 6. Validation and Branch Test

- [ ] `task lint`
- [ ] `task dev:validate`
- [ ] `task dev:start`
- [ ] `kubectl get gateway -n network <gateway-name>`
- [ ] Browser test:
  - [ ] unauthenticated user gets Google redirect
  - [ ] allowlisted user gets access
  - [ ] non-allowlisted user lands on `/denied`
  - [ ] logout lands on `/logged-out`
- [ ] `task dev:stop` (required)
