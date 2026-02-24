# Google OAuth Setup

This guide explains how to create Google OAuth credentials for Envoy Gateway OIDC and exactly where
to store each value in this repository.

______________________________________________________________________

## What Google values you need

From Google Cloud Console, you need:

- OAuth Client ID
- OAuth Client Secret
- Authorized redirect URI per OAuth Gateway hostname

______________________________________________________________________

## 1) Create the OAuth client in Google Cloud

1. Open <https://console.cloud.google.com/apis/credentials>
2. Click **Create Credentials** -> **OAuth client ID**
3. Choose **Web application**
4. Add authorized redirect URIs for each OAuth Gateway:
   - `https://oauth.<YOUR_DOMAIN>/oauth2/callback`
   - `https://oauth-internal.<YOUR_DOMAIN>/oauth2/callback` (if using internal gateway)
5. Save and copy the Client ID + Client Secret

______________________________________________________________________

## 2) Where to put each value in this repo

## Client Secret (sensitive)

Store in:

- `kubernetes/apps/network/envoy-gateway/app/oauth-client-secret.sops.yaml`

Field:

- `stringData.client-secret`

This file must stay SOPS-encrypted in Git.

## Client ID (not secret, but still kept in encrypted policy spec here)

Store in:

- `kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml`
- `kubernetes/apps/network/envoy-gateway/app/oauth-policy-internal.sops.yaml` (if used)

Field:

- `spec.oidc.clientID`

## Redirect/logout URLs

Store in each policy file above:

- `spec.oidc.redirectURL`
- `spec.oidc.logoutRedirectURL`

These must match the Google OAuth redirect URI hostnames exactly.

______________________________________________________________________

## 3) Update files safely (SOPS workflow)

```bash
# decrypt
sops --decrypt kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml > /tmp/oauth-policy.yaml

# edit /tmp/oauth-policy.yaml

# re-encrypt
sops --encrypt /tmp/oauth-policy.yaml > kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml
rm /tmp/oauth-policy.yaml
```

Use the same flow for `oauth-policy-internal.sops.yaml` and `oauth-client-secret.sops.yaml`.

______________________________________________________________________

## 4) Required related manifests

After updating credentials/policies, verify these references are present:

- `kubernetes/apps/network/envoy-gateway/app/kustomization.yaml`
  - includes `oauth-client-secret.sops.yaml`
  - includes policy files (`oauth-policy.sops.yaml`, `oauth-policy-internal.sops.yaml`)
- `kubernetes/apps/network/envoy-gateway/app/envoy.yaml`
  - OAuth Gateways have correct hostnames
  - OAuth Gateways include `home-ops.io/cloudflare-dns: "true"` label

______________________________________________________________________

## 5) Validate before/after push

```bash
task lint
task dev:validate
```

For branch testing:

```bash
task dev:start
kubectl get gateway -n network envoy-oauth envoy-oauth-internal --show-labels
kubectl get securitypolicy -n network envoy-oauth-policy envoy-oauth-internal-policy
task dev:stop
```

______________________________________________________________________

## Related docs

- [OIDC Troubleshooting](./OIDC-TROUBLESHOOTING.md)
- [SecurityPolicy Change Playbook](./SECURITYPOLICY-CHANGE-PLAYBOOK.md)
- [Gateway Onboarding Checklist](./GATEWAY-ONBOARDING-CHECKLIST.md)
