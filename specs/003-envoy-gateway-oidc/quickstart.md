# Quickstart: Envoy Gateway OIDC with Google OAuth

## Prerequisites

- `age.key` present in the repo root (needed to encrypt/decrypt SOPS files)
- Cluster running, Flux reconciling
- A new unused IP from the MetalLB pool (check current allocations: `kubectl get svc -A | grep LoadBalancer`)
- A Google Cloud project

______________________________________________________________________

## Step 1: Create a Google OAuth Application

1. Go to [Google API Console → Credentials](https://console.cloud.google.com/apis/credentials)
2. Click **Create Credentials → OAuth 2.0 Client ID**
3. Application type: **Web application**
4. Name: `home-ops` (or any name)
5. Authorized redirect URIs:
   - `https://oauth.<YOUR_DOMAIN>/oauth2/callback` (one per OAuth Gateway you create)
6. Click **Create** → Copy the **Client ID** and **Client Secret**

______________________________________________________________________

## Step 2: Create the OAuth Client Secret (SOPS-encrypted)

```bash
# Fill in your actual values
CLIENT_SECRET="<paste client secret from Google Console>"

# Create the Kubernetes Secret manifest and immediately encrypt it
cat <<EOF | sops --encrypt --input-type=yaml --output-type=yaml /dev/stdin \
  > kubernetes/apps/network/envoy-gateway/app/oauth-client-secret.sops.yaml
apiVersion: v1
kind: Secret
metadata:
  name: google-oauth-client-secret
  namespace: network
stringData:
  client-secret: "${CLIENT_SECRET}"
EOF
```

______________________________________________________________________

## Step 3: Add the OAuth Gateway to `envoy.yaml`

Open `kubernetes/apps/network/envoy-gateway/app/envoy.yaml` and append a new Gateway:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: envoy-oauth
  namespace: network
  labels:
    home-ops.io/cloudflare-dns: 'true'
    home-ops.io/oauth-gateway: 'true'
  annotations:
    external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
    lbipam.cilium.io/ips: 192.168.1.149    # Choose an unused MetalLB IP
spec:
  gatewayClassName: envoy
  infrastructure:
    annotations:
      external-dns.alpha.kubernetes.io/hostname: oauth.${SECRET_DOMAIN}
  listeners:
    - name: http
      protocol: HTTP
      port: 80
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: ${SECRET_DOMAIN/./-}-production-tls
            namespace: network
      allowedRoutes:
        namespaces:
          from: All
```

> Keep the `home-ops.io/cloudflare-dns: "true"` label on OAuth Gateways. `cloudflare-dns` uses
> `--gateway-label-filter=home-ops.io/cloudflare-dns=true`, so missing labels prevent DNS records
> from being created.

Also update the `https-redirect` HTTPRoute at the bottom of `envoy.yaml` to add the new Gateway:

```yaml
parentRefs:
  - name: envoy-external
  - name: envoy-internal
  - name: envoy-oauth   # Add this line
```

______________________________________________________________________

## Step 4: Create the SecurityPolicy (SOPS-encrypted)

```bash
CLIENT_ID="<paste client ID from Google Console>"
DOMAIN="example.com"  # Your actual domain

# Create a plaintext SecurityPolicy, then encrypt it
cat <<EOF | sops --encrypt --input-type=yaml --output-type=yaml /dev/stdin \
  > kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: envoy-oauth-policy
  namespace: network
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: envoy-oauth
  oidc:
    provider:
      issuer: "https://accounts.google.com"
    clientID: "${CLIENT_ID}"
    clientSecret:
      name: google-oauth-client-secret
      namespace: network
    redirectURL: "https://oauth.${DOMAIN}/oauth2/callback"
    logoutPath: "/logout"
    logoutRedirectURL: "https://oauth.${DOMAIN}/logged-out"
    cookieDomain: "${DOMAIN}"
  jwt:
    providers:
      - name: google
        issuer: "https://accounts.google.com"
        remoteJWKS:
          uri: "https://www.googleapis.com/oauth2/v3/certs"
  authorization:
    defaultAction: Deny
    rules:
    - name: allow-whitelist
      action: Allow
      principal:
        jwt:
          provider: google
          claims:
          - name: email_verified
            values:
            - "true"
          - name: email
            values:
            - "you@gmail.com"          # Add allowlisted email addresses here
            - "friend@example.com"
EOF
```

______________________________________________________________________

## Step 5: Register the Files in the App Kustomization

Open `kubernetes/apps/network/envoy-gateway/app/kustomization.yaml` and add the new files:

```yaml
resources:
  - certificate.yaml
  - envoy.yaml
  - helmrelease.yaml
  - ocirepository.yaml
  - podmonitor.yaml
  - oauth-client-secret.sops.yaml  # Add
  - oauth-policy.sops.yaml  # Add
```

______________________________________________________________________

## Step 6: Deploy the Static Error Pages

The `oauth-pages` app in `kubernetes/apps/default/oauth-pages/` provides `/denied` and
`/logged-out` pages. Run `task lint && task dev:validate` to verify before deploying.
See `kubernetes/apps/default/oauth-pages/` for the full app structure.

Also add an HTTPRoute entry so each OAuth Gateway routes to the static pages service:

- `/denied` → `oauth-pages` service in `default` namespace
- `/logged-out` → `oauth-pages` service in `default` namespace

______________________________________________________________________

## Step 7: Opt an App into OAuth

To protect an existing app (e.g., `myapp`) with the OAuth Gateway:

1. Open the app's `helmrelease.yaml` (or wherever `route.parentRefs` is configured)
2. Change the Gateway reference:

```yaml
# Before (public access)
route:
  parentRefs:
    - name: envoy-external

# After (OAuth-protected)
route:
  parentRefs:
    - name: envoy-oauth
```

3. Run `task lint && task dev:validate` — then commit and push.
4. The app immediately becomes OAuth-protected. Users not on the whitelist see the `/denied` page.

______________________________________________________________________

## Step 8: Validate and Deploy

```bash
task lint            # auto-fix formatting
task dev:validate    # render all manifests offline — must pass
task dev:start       # push branch, test on live cluster
task dev:stop        # ALWAYS run this when done
```

______________________________________________________________________

## Managing the Email Allowlist

### Add an email address

```bash
# Decrypt
sops --decrypt kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml \
  > /tmp/policy.yaml

# Edit /tmp/policy.yaml — add email to:
# spec.authorization.rules[0].principal.jwt.claims[0].values[]

# Re-encrypt
sops --encrypt /tmp/policy.yaml \
  > kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml

rm /tmp/policy.yaml   # never leave plaintext around

git add kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml
git commit -m "🔐 add user to oauth whitelist"
git push
```

### Remove an email address

Same process — decrypt, remove the email from `values[]`, re-encrypt, commit.

### Revoke access immediately

Same process — after pushing, Flux reconciles within ~10 minutes. The user's existing
session cookie remains valid until it expires. For immediate revocation, restart the Envoy
Gateway pods to clear session state:

```bash
kubectl rollout restart deployment -n network -l app.kubernetes.io/name=envoy-gateway
```

______________________________________________________________________

## Adding a Second OAuth Gateway

To add a second OAuth Gateway with a different email allowlist (e.g., `envoy-oauth-internal`):

1. Add a second Gateway resource in `envoy.yaml` with a new IP and DNS name
2. Create `oauth-policy-internal.sops.yaml` with a different email list
3. Add both to `kustomization.yaml`
4. No changes needed to the static pages app (it's already accessible to all OAuth Gateways)

Apps route to whichever Gateway they reference in `parentRefs`.

______________________________________________________________________

## Architecture Summary

```
Google OIDC
    │
    ▼
OAuth Gateway (e.g., envoy-oauth @ 192.168.1.149)
    │  └─ SecurityPolicy: OIDC + email allowlist (SOPS-encrypted)
    │
    ├─── /denied, /logged-out → oauth-pages nginx (default namespace)
    └─── /myapp, /otherapp  → protected app services (any namespace)

Public Gateway (envoy-external @ 192.168.1.148) ← unchanged
    └─── /publicapp → unprotected app services
```
