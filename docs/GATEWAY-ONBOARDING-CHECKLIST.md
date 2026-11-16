# Gateway & Pomerium Route Onboarding Checklist

Use this checklist whenever onboarding a new Envoy Gateway or Pomerium SSO-protected application.

______________________________________________________________________

## 1. Public or LAN-Only App (Envoy Gateway)

- [ ] Choose `envoy-external` (public) or `envoy-internal` (LAN-only)
- [ ] Configure `route.app` in the app's `values.yaml`
- [ ] Include `gateway.networking.k8s.io/v1/HTTPRoute` under `apiVersions` in the app's `kustomization.yaml`
- [ ] For custom external domains outside `*.${SECRET_DOMAIN}`, add listener + certificate in
  `kubernetes/workloads/network/envoy-gateway/` and a rule in `cloudflare-tunnel/values.yaml`

______________________________________________________________________

## 2. OAuth-Protected App (Pomerium SSO)

- [ ] Decrypt `kubernetes/workloads/network/pomerium/ingresses.sops.yaml`
- [ ] Add a `networking.k8s.io/v1` `Ingress` item in the app's namespace with:
  - `spec.ingressClassName: pomerium`
  - `ingress.pomerium.io/policy` matching `Admins` or `Users` (via YAML anchors `&admins`/`&users` before encryption)
  - `ingress.pomerium.io/allow_websockets: "true"` if the app uses WebSockets
- [ ] Re-encrypt `ingresses.sops.yaml` with `sops --encrypt` (verify `ENC[AES256_GCM` is present)
- [ ] Add explicit hostname entry in `kubernetes/workloads/network/cloudflare-tunnel/values.yaml`
  **before** `*.${SECRET_DOMAIN}` targeting `https://pomerium-proxy.pomerium.svc.cluster.local:443`
  with `originServerName: oauth.${SECRET_DOMAIN}`
- [ ] If the app has a `CiliumNetworkPolicy`, allow ingress from `pomerium-proxy` pods:
  - `k8s:io.kubernetes.pod.namespace: pomerium`
  - `app.kubernetes.io/name: pomerium`
  - `app.kubernetes.io/component: proxy`

______________________________________________________________________

## 3. Validation and Branch Test

- [ ] `task lint`
- [ ] `task dev:validate`
- [ ] `task dev:start`
- [ ] `kubectl get pomerium -n pomerium global`
- [ ] `kubectl get ingress -A --field-selector spec.ingressClassName=pomerium`
- [ ] Browser test:
  - [ ] unauthenticated user redirects to Google login via `https://oauth.<domain>/oauth2/callback`
  - [ ] allowlisted user gets access
  - [ ] non-allowlisted user receives 403 Forbidden
  - [ ] `https://<app-host>/.pomerium/sign_out` clears session
- [ ] `task dev:stop` (required)
