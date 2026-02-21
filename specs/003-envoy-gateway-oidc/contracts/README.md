# contracts/

Template manifests for the Envoy Gateway OIDC feature. These are reference YAML documents
showing the exact resource structure. Replace `<PLACEHOLDER>` values with real data.

Files:

- `oauth-gateway.yaml` — New OAuth-enabled Gateway
- `oauth-policy.sops.yaml` — SecurityPolicy with OIDC + email allowlist (SOPS-encrypted before commit)
- `oauth-client-secret.sops.yaml` — Kubernetes Secret for Google OAuth credentials (SOPS-encrypted)
- `httproute-app-optin.yaml` — How an app opts into an OAuth Gateway
- `static-pages-httproute.yaml` — HTTPRoute for static error pages
