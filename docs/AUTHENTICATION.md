# Authentication

Public protected requests follow Cloudflare Tunnel → the admin/users Envoy Gateway →
Google OIDC → JWT signature/issuer/audience verification → verified-email check →
email allowlist → the app's own authentication. Public apps use `envoy-external`;
LAN and Tailscale paths have independent access controls.

## Deployment prerequisites

Complete these external changes before deploying the authentication hardening:

1. Register each protected app's `/oauth2/callback` URI in Google. See
   [Google setup](GOOGLE-OAUTH-SETUP.md). Host-scoped cookies require callbacks on the
   app host; the shared `oauth` callback alone is no longer sufficient.
2. Add `LUNCHMONEY_APP_API_KEY` to the existing `lunchmoney` 1Password item, confirm
   External Secrets has synchronized it, and configure `X-API-Key` in all Lunch Money
   clients, including OpenClaw. The dashboard also requires the header; a plain browser
   visit receives 401. See [Lunch Money setup](LUNCHMONEY-SETUP.md).
3. Replace broad tailnet allow-all grants with the narrow policy in
   [Tailscale setup](TAILSCALE-SETUP.md), adapting membership to your actual users.
   Console policy changes are external to this repository.
4. Clear legacy root-domain OAuth cookies from browsers and sign in again per app.
   Google may reuse its own login session, but Envoy sessions are now host-scoped.
   Keep old Google callback registrations until the rollout is verified.
5. Run full validation with the age key, then branch-test with `kubeconfig` available.
   Always finish an initiated branch test with `task dev:stop`.

These prerequisites are required for rollout. Opening or merging a PR does not configure
Google, 1Password, Tailscale, or browser cookies. Missing Google registrations break login;
missing/empty Lunch Money keys keep its proxy unavailable rather than accepting requests.

## Session boundaries

OAuth cookies are Secure, HttpOnly, SameSite=Lax, and host-scoped. ID/access-token cookie
encryption is disabled because the pinned controller cannot feed decrypted tokens into its
JWT verifier. ID tokens remain Google-signed; OAuth cookies are stripped before contacting
apps. This trades browser-side token confidentiality for the supported JWT-cookie path.
Revisit encryption when upgrading to a controller with implemented ID-token forwarding. Public sibling
apps do not receive newly issued cookies. Applications on different hosts do not share an
Envoy session. Encrypted policy files preserve client IDs and email allowlists; the public
`oauth-hardening.yaml` patch overrides baseline security settings after SOPS decryption.
Audience replacements use each policy's own client ID. The verified-email extension checks
Google's boolean claim directly in verified JWT metadata, avoiding string coercion and
spoofable client identity headers.

Keep application authentication on privileged apps, including Paseo's Tailscale endpoint.
Lunch Money's proxy protects REST, MCP, dashboard, and metrics with a required API key;
its raw application port is isolated. This is a shared service credential, not per-user
authorization. Tailnet grants should restrict which users can even reach the service.
Anyone with the key has the same application access until the key is rotated.

Only exact denied/logged-out utility rules bypass gateway authentication. Callback and
logout stay in the OIDC flow. Utility hostnames are explicit: an exact app hostname can
outrank a wildcard route even when the wildcard has a more specific path.
Application HTTP 403 responses remain HTTP 403; denied users can visit `/denied` explicitly.

Route authors are trusted: a more specific SecurityPolicy can replace Gateway settings.
CI rejects unexpected policies until the override is reviewed and its invariant checks
are updated. Do not grant untrusted workloads permission to create routes or policies.

## Validation and monitoring

```bash
task lint
task dev:auth:test
task dev:validate
```

Without an age key, use `task dev:validate:ci`. Both render modes validate built-in resource
schemas and Gateway/Envoy custom resources against the CRDs shipped by the rendered chart.
They also check audience binding, cookie scope, default deny, ID-token cookie extraction,
verified-email filter attachment, public exceptions, utility hostname coverage, tunnel group
mapping, and Lunch Money's required key/proxy/isolation. Bootstrap-owned ArgoCD routes are
included. Custom resource CEL admission expressions still require a live API server.
Placeholder rendering cannot verify real emails, encrypted file integrity, or live behavior.

`task dev:auth:test` requires nginx and uses an isolated Python 3.14/Lupa environment to run
the actual verified-email Lua code. It also tests mutations of rendered security settings,
strict CRD validation, and REST/MCP requests through the actual nginx configuration with
synthetic credentials. CI installs nginx for this task; production images are not deployed
by these tests. Review the app's `/api` key-check contract when upgrading Lunch Money.

During branch testing and after merge, verify:

- Gateway and policy `Accepted`/`Programmed` status; ArgoCD health alone is insufficient.
- Signed-out access redirects to Google with an exact app-host callback.
- Allowed users succeed; denied users get 403; application 403s retain their status.
- Cookies have no Domain attribute; no OAuth cookies are sent to `echo` or another app.
- Callback and logout work, including token expiry and refresh across Envoy replicas.
- Lunch Money rejects missing/wrong keys on both `/api` and `/mcp`, and raw port 8000
  is unreachable from another workload. Test Service and pod IP paths separately.
- The removed user's existing session is denied on its next request after reconciliation;
  active WebSockets and native app sessions are tested separately.

Envoy proxy metrics are already scraped, but these checks do not provide a full synthetic
login monitor. Google, DNS, Cloudflare, certificate renewal, and the physical node remain
shared dependencies. Two proxy replicas on the documented single node do not provide
node-level availability. See the [revocation playbook](SECURITYPOLICY-CHANGE-PLAYBOOK.md#revocation)
and [post-merge checklist](POST-MERGE-VERIFICATION.md).
