# Google OAuth Setup (Pomerium)

This guide explains how to configure Google OAuth credentials for Pomerium Ingress Controller and
where each value lives in this repository.

______________________________________________________________________

## What Google values you need

From Google Cloud Console, you need:

- OAuth Client ID
- OAuth Client Secret
- Authorized redirect URI: `https://oauth.<YOUR_DOMAIN>/oauth2/callback`

______________________________________________________________________

## 1) Create or reuse the OAuth client in Google Cloud

1. Open <https://console.cloud.google.com/apis/credentials>
2. Click **Create Credentials** -> **OAuth client ID** (or edit your existing Web application client)
3. Choose **Web application**
4. Ensure the authorized redirect URI includes:
   - `https://oauth.<YOUR_DOMAIN>/oauth2/callback`
5. Save and copy the Client ID + Client Secret

______________________________________________________________________

## 2) Migrating from the legacy Envoy OAuth setup

If you are upgrading an existing cluster that used `envoy-gateway/oauth-policy.sops.yaml` and
`envoy-gateway/oauth-client-secret.sops.yaml`, run the migration script locally with `age.key`:

```bash
./scripts/migrate-oauth-to-pomerium.sh
```

This decrypts the legacy credentials and `Admins` / `Users` email lists from `origin/main` (or
local disk) and populates encrypted Pomerium files in `kubernetes/workloads/network/pomerium/`.

______________________________________________________________________

## 3) Where values are stored

- **Google IdP credentials**: `kubernetes/workloads/network/pomerium/google-idp-secret.sops.yaml`
  - `stringData.client_id`
  - `stringData.client_secret`
  - Must remain SOPS-encrypted (`ENC[AES256_GCM,...]`).
- **Pomerium global settings**: `kubernetes/workloads/network/pomerium/pomerium.yaml`
  - `spec.authenticate.url`: `https://oauth.${SECRET_DOMAIN}`
  - `spec.certificates`: `network/${SECRET_DOMAIN/./-}-production-tls`
  - `spec.identityProvider`: `provider: google`, `secret: pomerium/google-idp`
- **Access groups (`Admins` & `Users`)**: `kubernetes/workloads/network/pomerium/ingresses.sops.yaml`
  - Defines PPL policies using `&admins` and `&users` YAML anchors
  - Only `ingress.pomerium.io/policy` annotations are SOPS-encrypted (via `.sops.yaml`)

______________________________________________________________________

## 4) Update files safely (SOPS workflow)

```bash
# decrypt
sops --decrypt kubernetes/workloads/network/pomerium/google-idp-secret.sops.yaml > /tmp/google-idp.yaml

# edit /tmp/google-idp.yaml

# re-encrypt
sops --encrypt /tmp/google-idp.yaml > kubernetes/workloads/network/pomerium/google-idp-secret.sops.yaml
rm /tmp/google-idp.yaml
```

______________________________________________________________________

## 5) Validate before/after push

```bash
task lint
task dev:validate
```

For branch testing:

```bash
task dev:start
kubectl get pomerium -n pomerium global
kubectl get pods,svc,pvc -n pomerium
kubectl get ingress -A -l app.kubernetes.io/part-of=pomerium-sso
task dev:stop
```

______________________________________________________________________

## Related docs

- [OIDC Troubleshooting](./OIDC-TROUBLESHOOTING.md)
- [SecurityPolicy Change Playbook](./SECURITYPOLICY-CHANGE-PLAYBOOK.md)
- [Gateway Onboarding Checklist](./GATEWAY-ONBOARDING-CHECKLIST.md)
