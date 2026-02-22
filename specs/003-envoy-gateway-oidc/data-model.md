# Data Model: Envoy Gateway OIDC with Google OAuth

## Kubernetes Resource Inventory

### 1. OAuth Gateway (`Gateway`)

One resource per OAuth-protected access group (e.g., `envoy-oauth` for the primary group,
`envoy-oauth-internal` for additional groups).

**Namespace**: `network`
**File**: `kubernetes/apps/network/envoy-gateway/app/envoy.yaml` (appended)

| Field                                                                          | Value                                 | Notes                                |
| ------------------------------------------------------------------------------ | ------------------------------------- | ------------------------------------ |
| `metadata.name`                                                                | `envoy-oauth` or `envoy-oauth-<name>` | e.g., `envoy-oauth-internal`         |
| `spec.gatewayClassName`                                                        | `envoy`                               | Reuses existing GatewayClass         |
| `spec.infrastructure.annotations["lbipam.cilium.io/ips"]`                      | `"192.168.1.149"`                     | New IP per Gateway from MetalLB pool |
| `spec.infrastructure.annotations["external-dns.alpha.kubernetes.io/hostname"]` | `oauth.<domain>`                      | Per-Gateway DNS name                 |
| `spec.listeners[https].tls.certificateRefs`                                    | `${SECRET_DOMAIN/./-}-production-tls` | Reuses existing wildcard TLS cert    |
| `spec.listeners[https].allowedRoutes.namespaces.from`                          | `All`                                 | Allows HTTPRoutes from any namespace |

**Relationships**: Referenced by SecurityPolicy (`targetRefs`), HTTPRoutes (`parentRefs`).

______________________________________________________________________

### 2. SecurityPolicy (`SecurityPolicy`) — SOPS-encrypted

One SOPS-encrypted file per OAuth Gateway. Contains OIDC config and email allowlist.

**Namespace**: `network`
**File**: `kubernetes/apps/network/envoy-gateway/app/oauth-policy-<name>.sops.yaml`
**API version**: `gateway.envoyproxy.io/v1alpha1`

| Field                                                              | Value                                    | Notes                                       |
| ------------------------------------------------------------------ | ---------------------------------------- | ------------------------------------------- |
| `metadata.name`                                                    | `envoy-oauth-<name>-policy`              | Matches Gateway name                        |
| `spec.targetRefs[0].kind`                                          | `Gateway`                                | Gateway-level protection                    |
| `spec.targetRefs[0].name`                                          | `envoy-oauth-<name>`                     | References the OAuth Gateway                |
| `spec.oidc.provider.issuer`                                        | `https://accounts.google.com`            | Google OIDC issuer                          |
| `spec.oidc.clientID`                                               | `<GOOGLE_CLIENT_ID>`                     | From Google Console                         |
| `spec.oidc.clientSecret.name`                                      | `google-oauth-client-secret`             | References Secret below                     |
| `spec.oidc.redirectURL`                                            | `https://oauth.<domain>/oauth2/callback` | Registered in Google Console                |
| `spec.oidc.logoutPath`                                             | `/logout`                                | Clears session cookies                      |
| `spec.oidc.logoutRedirectURL`                                      | `https://oauth.<domain>/logged-out`      | Logout confirmation page                    |
| `spec.oidc.cookieDomain`                                           | `<SECRET_DOMAIN>`                        | Root domain for cross-subdomain sessions    |
| `spec.authorization.defaultAction`                                 | `Deny`                                   | Fail-closed: deny unless explicitly allowed |
| `spec.authorization.rules[0].action`                               | `Allow`                                  | One Allow rule for whitelisted emails       |
| `spec.authorization.rules[0].principal.jwt.provider`               | `google`                                 | References OIDC provider                    |
| `spec.authorization.rules[0].principal.jwt.claims[email].values[]` | `["user@example.com", ...]`              | Allowlisted emails (lowercase)              |

**Encryption**: The entire manifest is SOPS-encrypted using the cluster's age key.
**Lifecycle**: Decrypted by Flux's kustomize-controller at reconcile time. Update by
decrypt → edit `values[]` → re-encrypt → commit → push.

**Constraints**:

- Email addresses MUST be lowercase (Google returns lowercase; consistency enforced by convention)
- `defaultAction: Deny` is mandatory (fail-closed per FR-008)
- Empty `values[]` results in all users being denied (fail-closed per spec)

______________________________________________________________________

### 3. OAuth Client Secret (`Secret`) — SOPS-encrypted

Single Kubernetes Secret per cluster (shared across all OAuth Gateways using the same Google app).

**Namespace**: `network`
**File**: `kubernetes/apps/network/envoy-gateway/app/oauth-client-secret.sops.yaml`

| Field                   | Value                            | Notes                        |
| ----------------------- | -------------------------------- | ---------------------------- |
| `metadata.name`         | `google-oauth-client-secret`     | Referenced by SecurityPolicy |
| `data["client-secret"]` | `<base64-encoded client secret>` | From Google Console          |

**Note**: `clientID` is stored in the SecurityPolicy manifest itself (not a secret), consistent
with Envoy Gateway's API design. Only `clientSecret` requires a Kubernetes Secret.

______________________________________________________________________

### 4. Static Pages Deployment (nginx `HelmRelease`)

Single deployment serving both the access-denied page and the logout confirmation page.

**Namespace**: `default`
**File**: `kubernetes/apps/default/oauth-pages/app/helmrelease.yaml`

| Field           | Value                     | Notes                                        |
| --------------- | ------------------------- | -------------------------------------------- |
| `metadata.name` | `oauth-pages`             |                                              |
| Chart           | `app-template`            | Reuses existing chart pattern                |
| Container image | `nginx:alpine`            | Minimal static server                        |
| ConfigMap       | `oauth-pages-html`        | Contains `denied.html` and `logged-out.html` |
| Mount path      | `/usr/share/nginx/html/`  | Nginx webroot                                |
| Service port    | `80`                      | HTTP (TLS terminated at Gateway)             |
| Resources       | `cpu: 5m`, `memory: 16Mi` | Static server needs minimal resources        |

**Pages served**:

| Path          | File              | Purpose                                         |
| ------------- | ----------------- | ----------------------------------------------- |
| `/denied`     | `denied.html`     | Access denied — shown to non-whitelisted users  |
| `/logged-out` | `logged-out.html` | Logout confirmation — shown after session clear |

______________________________________________________________________

### 5. Static Pages HTTPRoute (`HTTPRoute`)

Routes `/denied` and `/logged-out` on each OAuth Gateway to the static pages service.

**Namespace**: `default`
**File**: `kubernetes/apps/default/oauth-pages/app/httproute.yaml`

| Field                                     | Value                | Notes                       |
| ----------------------------------------- | -------------------- | --------------------------- |
| `parentRefs[*].name`                      | `envoy-oauth-<name>` | One entry per OAuth Gateway |
| `rules[denied].matches[0].path.value`     | `/denied`            | Access denied path          |
| `rules[logged-out].matches[0].path.value` | `/logged-out`        | Logout confirmation path    |
| `rules[*].backendRefs[0].name`            | `oauth-pages`        | Static pages Service        |
| `rules[*].backendRefs[0].namespace`       | `default`            |                             |

**Important**: These routes must be registered on each OAuth Gateway so that the OIDC callback
path (`/oauth2/callback`) and error paths work within the Gateway's routing context.

______________________________________________________________________

### 6. BackendTrafficPolicy — 403 Response Override

Intercepts 403 responses from the OAuth Gateway and serves the custom access-denied page.

**Namespace**: `network`
**File**: `kubernetes/apps/network/envoy-gateway/app/envoy.yaml` (appended) or separate file

| Field                                            | Value                           | Notes                            |
| ------------------------------------------------ | ------------------------------- | -------------------------------- |
| `spec.targetSelectors[0].kind`                   | `Gateway`                       | Applied to OAuth Gateway(s)      |
| `spec.responseOverride[0].match.statusCodes[]`   | `403`                           | Intercept authorization failures |
| `spec.responseOverride[0].response.redirect.url` | `https://oauth.<domain>/denied` | Custom denied page               |

______________________________________________________________________

## State Transitions

### User Authentication Flow

```
Unauthenticated Request
  → [Envoy OIDC filter] → Redirect to Google login
  → [Google] → User enters credentials
  → [Google] → Redirect to /oauth2/callback with code
  → [Envoy] → Exchange code for ID token (JWT with email claim)
  → [Envoy authorization] → Check email claim against allowlist
      → Email IN allowlist → Allow → Redirect to original destination URL
      → Email NOT in allowlist → Deny 403 → ResponseOverride → /denied page
```

### Email Whitelist Update Flow

```
Operator edits allowlist
  → sops --decrypt oauth-policy.sops.yaml (requires age.key)
  → Edit authorization.rules[0].principal.jwt.claims[email].values[]
  → sops --encrypt → oauth-policy.sops.yaml
  → git commit + push
  → Flux reconciles (< 10 minutes)
  → New SecurityPolicy applied to cluster
  → Existing user sessions unaffected until next re-authentication
```

### App Opt-In Flow

```
Operator wants to protect app with OAuth
  → Change app's HTTPRoute parentRefs.name from "envoy-external" to "envoy-oauth"
  → git commit + push → Flux reconciles
  → App now protected (no changes to SecurityPolicy, whitelist, or other apps)
```

______________________________________________________________________

## Naming Conventions

| Resource type    | Pattern                                                                                                | Example                                              |
| ---------------- | ------------------------------------------------------------------------------------------------------ | ---------------------------------------------------- |
| OAuth Gateway    | `envoy-oauth` (primary) or `envoy-oauth-<group>`                                                       | `envoy-oauth-internal`                               |
| SecurityPolicy   | `envoy-oauth-policy` (primary) or `envoy-oauth-<group>-policy`                                         | `envoy-oauth-internal-policy`                        |
| SOPS policy file | `oauth-policy.sops.yaml` (primary) or `oauth-policy-<group>.sops.yaml`                                 | `oauth-policy-internal.sops.yaml`                    |
| DNS hostname     | `oauth.${SECRET_DOMAIN}` (primary) or `oauth-<group>.${SECRET_DOMAIN}`                                 | `oauth-internal.example.com`                         |
| Redirect URL     | `https://oauth.<domain>/oauth2/callback` (primary) or `https://oauth-<group>.<domain>/oauth2/callback` | `https://oauth-internal.example.com/oauth2/callback` |
