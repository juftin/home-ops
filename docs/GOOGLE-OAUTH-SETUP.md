# Google OAuth Setup

Envoy Gateway authenticates browser requests with Google OIDC. See
[Authentication](AUTHENTICATION.md) for migration prerequisites, trust boundaries, and tests.

## Google client

Create a **Web application** OAuth client in
<https://console.cloud.google.com/apis/credentials>. Register an exact callback URI
for every protected app hostname **before deploying host-scoped sessions**:

- `https://paseo.<YOUR_DOMAIN>/oauth2/callback`
- `https://herdr.<YOUR_DOMAIN>/oauth2/callback`
- `https://hermes.<YOUR_DOMAIN>/oauth2/callback`
- `https://openclaw.<YOUR_DOMAIN>/oauth2/callback`
- `https://grafana.<YOUR_DOMAIN>/oauth2/callback`
- `https://argocd.<YOUR_DOMAIN>/oauth2/callback`

Retain the existing `oauth`, `oauth-users`, and `oauth-internal` callback registrations
while migrating. ArgoCD's own OIDC login also needs its existing `/auth/callback`
registration; the gateway callback does not replace it.

Use strong Google account authentication, preferably passkeys or security keys.
Google account settings and OAuth console changes are external to GitOps.

## Credential storage

- Client secret: `kubernetes/apps/network/envoy-gateway/app/oauth-client-secret.sops.yaml`,
  `stringData.client-secret`.
- Client IDs and email allowlists: `oauth-policy.sops.yaml` (admins/users) and
  `oauth-policy-internal.sops.yaml`, in the same directory.
- Include admin emails in the users list when admins should also have users access.

Use `sops edit <file>` with the age key available. Keep all secret files encrypted.
Follow [the policy playbook](SECURITYPOLICY-CHANGE-PLAYBOOK.md) for allowlist changes.

## Public security settings

`oauth-hardening.yaml` is a Kustomize JSON patch applied after decryption. It enforces
Google issuer/JWKS, default deny, host-scoped signed token cookies, HTTPS callbacks on the
request host, and JWT extraction from the ID-token cookie. Kustomize replacements copy each policy's
OIDC client ID into its JWT audience list. Editing these settings in the encrypted base
will not override the public hardening patch.

Google's `email_verified` is a boolean. The pinned Envoy Gateway's native JWT
claim authorization supports strings and string arrays only. `oauth-verified-email.yaml`
checks the boolean in verified JWT metadata after JWT verification and before authorization.
Missing, false, string, and numeric values are rejected. OAuth cookies are removed before upstream forwarding while app session cookies are retained.
The pinned controller cannot forward decrypted ID tokens into JWT verification, even though
its API exposes a forwarding field. Token encryption is explicitly disabled for its supported
JWT-cookie path; ID tokens remain signed by Google. Cookies are Secure, HttpOnly, SameSite=Lax,
and host-scoped. Do not re-enable encryption without testing JWT verification against the
exact controller version.

## Validation

```bash
task lint
task dev:auth:test
task dev:validate
```

Use `task dev:validate:ci` without the age key. Placeholder validation checks public
security settings and schemas, but cannot verify real email values or SOPS integrity.
Branch testing requires `kubeconfig`; always run `task dev:stop` if testing was started.
