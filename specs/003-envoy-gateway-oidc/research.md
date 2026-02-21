# Research: Envoy Gateway OIDC with Google OAuth

## 1. Email Allowlist Enforcement via JWT Claim Authorization

**Decision**: Embed the email allowlist directly in the SecurityPolicy manifest using
`authorization.rules[*].principal.jwt.claims[name=email].values[]`.

**Rationale**: Envoy Gateway's `SecurityPolicy` supports native JWT claim-based authorization
(confirmed via official docs: `gateway.envoyproxy.io/docs/tasks/security/jwt-claim-authorization/`).
When OIDC is configured, Google's ID token (a JWT) includes an `email` claim. The
`authorization` section of the same SecurityPolicy can enforce claim-based allow rules. This
requires zero additional infrastructure.

**Alternatives considered**:

- *External authorization (ext_authz)*: Would require a sidecar/service to evaluate requests.
  Rejected — unnecessary infrastructure for a homelab where the email list is small and static.
- *OPA/Kyverno*: Policy engine approach. Rejected — adds significant complexity and a new
  component just for email matching.
- *Separate ConfigMap/Secret referenced by SecurityPolicy*: SecurityPolicy's authorization
  rules do not support dynamic claim value injection from Secrets. Rejected — not supported
  by the API.

**Key API structure**:

```yaml
authorization:
  defaultAction: Deny
  rules:
    - name: allow-whitelist
      action: Allow
      principal:
        jwt:
          provider: google        # name of OIDC/JWT provider in the SecurityPolicy
          claims:
            - name: email
              values:
                - user@example.com # lowercase; Google returns lowercase emails
```

**Verification note**: When `oidc` is configured in a SecurityPolicy, the OIDC provider is
also automatically available as a JWT provider for `authorization` rules. The provider name
in the authorization rules must match the provider name configured in `oidc` (or "google"
by convention when targeting Google's OIDC). Confirm during implementation.

______________________________________________________________________

## 2. Multi-Gateway Architecture

**Decision**: Add new `envoy-oauth-<name>` Gateways alongside existing public Gateways.
Each OAuth Gateway gets its own LoadBalancer IP (MetalLB `lbipam.cilium.io/ips` annotation),
its own SecurityPolicy, and its own SOPS-encrypted email allowlist.

**Rationale**: Existing `envoy-external` (192.168.1.148) and `envoy-internal` (192.168.1.147)
continue serving unprotected apps unchanged. Dedicated OAuth Gateways isolate auth config from
public routes and allow different whitelists per Gateway without per-route SecurityPolicies.

**Alternatives considered**:

- *Per-HTTPRoute SecurityPolicy*: Would require one SecurityPolicy per protected app, each
  with its own redirect URL registered in Google Console. Rejected — operational overhead
  scales with number of apps.
- *Single Gateway with mixed protected/unprotected routes*: Not supported cleanly; a
  Gateway-level SecurityPolicy protects all routes; HTTPRoute-level would require per-app policies.

**Required for each new OAuth Gateway**:

- New LoadBalancer IP from the MetalLB pool (operator configures in `envoy.yaml`)
- New DNS record pointing to that IP (handled by external-dns annotation)
- One redirect URL registered in Google Console (e.g., `https://oauth.<domain>/oauth2/callback`)
- SOPS-encrypted SecurityPolicy with OIDC config + email claims

______________________________________________________________________

## 3. SOPS Encryption Strategy

**Decision**: SOPS-encrypt the SecurityPolicy manifest (containing email addresses) and the
Kubernetes Secret (containing OAuth client credentials) as separate `.sops.yaml` files.

**Rationale**: Email addresses are PII and must not appear in plaintext in Git (spec FR-004,
FR-009, SC-004). Flux's kustomize-controller automatically decrypts `.sops.yaml` files in any
Kustomization path when the cluster's age key (`sops-age` secret in `flux-system`) is configured.
The `network` namespace's kustomization already includes `components/sops` at the namespace level.

**File placement**:

```
kubernetes/apps/network/envoy-gateway/app/
├── oauth-client-secret.sops.yaml      # Kubernetes Secret: client_id, client_secret
└── oauth-policy-<name>.sops.yaml      # SecurityPolicy: OIDC config + email claims
```

**Workflow for email list updates**:

```bash
# Decrypt (in repo root, age key must be present)
sops --decrypt kubernetes/apps/network/envoy-gateway/app/oauth-policy-external.sops.yaml \
  > /tmp/policy.yaml

# Edit email list in /tmp/policy.yaml, then re-encrypt
sops --encrypt /tmp/policy.yaml \
  > kubernetes/apps/network/envoy-gateway/app/oauth-policy-external.sops.yaml

# Commit and push — Flux reconciles automatically
git add kubernetes/apps/network/envoy-gateway/app/oauth-policy-external.sops.yaml
git commit -m "🔐 update oauth whitelist"
git push
```

______________________________________________________________________

## 4. Custom Error Pages

**Decision**: Deploy a lightweight nginx static server in the `default` namespace serving
two HTML pages: `/denied` (access denied) and `/logged-out` (logout confirmation). Use
Envoy Gateway's `BackendTrafficPolicy` `responseOverride` to intercept 403 responses and
redirect to the `/denied` page.

**Rationale**: The spec requires a custom access-denied page (FR-012) and a dedicated logout
page (FR-015). A single nginx deployment handles both pages, minimizing resource overhead.
`responseOverride` is supported in Envoy Gateway's BackendTrafficPolicy.

**Alternatives considered**:

- *Inline HTML in SecurityPolicy*: No such field exists in the SecurityPolicy API.
- *Separate deployments per page*: Unnecessary overhead for static HTML.

**Implementation note**: The `logoutRedirectURL` field in the OIDC SecurityPolicy config
specifies where users land after logout. Set to `https://oauth.<domain>/logged-out`.
The `/denied` page is served via `responseOverride` on 403 status codes.

______________________________________________________________________

## 5. Cookie Domain & Session Sharing

**Decision**: Set `cookieDomain` in each OAuth Gateway's SecurityPolicy to the cluster's
root domain (e.g., `${SECRET_DOMAIN}`). This allows a single login session to be shared
across all apps attached to the same OAuth Gateway.

**Rationale**: Envoy Gateway's OIDC SecurityPolicy supports a `cookieDomain` field that
sets the cookie's domain attribute, enabling cross-subdomain session sharing. Without this,
each app hostname would require a separate login. Confirmed in official OIDC task docs.

______________________________________________________________________

## 6. Google OAuth Application Setup

**Decision**: Use a single Google OAuth application (client ID + secret) cluster-wide, with
one redirect URL registered per OAuth Gateway.

**Required Google Console setup** (per OAuth Gateway):

1. Go to [Google API Console](https://console.developers.google.com/) → Credentials
2. Create OAuth 2.0 Client ID (Web Application type)
3. Add Authorized redirect URI: `https://oauth.<domain>/oauth2/callback`
4. Note the Client ID and Client Secret → encrypt into `oauth-client-secret.sops.yaml`

**Google's OIDC token** includes the following claims relevant to this feature:

- `email`: user's Google email (lowercase)
- `email_verified`: boolean — should be `true` for allowlisted users
- `iss`: `https://accounts.google.com`
- `sub`: unique user identifier

______________________________________________________________________

## 7. Existing Gateway Compatibility

**Decision**: Existing `envoy-external` and `envoy-internal` Gateways remain unchanged.
No SecurityPolicy is attached to them. Apps currently on those Gateways continue working
without modification.

**Confirmation**: All existing apps use `parentRefs` in their HelmRelease `route` values
to specify `envoy-external` or `envoy-internal`. Moving an app to an OAuth Gateway requires
only changing the `parentRefs.name` value — no other app configuration changes needed.
