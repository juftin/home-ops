# Contract: Pomerium Global Configuration & Secrets

## Pomerium CRD (`kubernetes/workloads/network/pomerium/pomerium.yaml`)

- **API Version**: `ingress.pomerium.io/v1`
- **Kind**: `Pomerium`
- **Name / Namespace**: `global` / `pomerium`
- **Contract**:
  - `spec.authenticate.url` MUST be `https://oauth.${SECRET_DOMAIN}` so the Google OAuth callback remains `https://oauth.${SECRET_DOMAIN}/oauth2/callback`.
  - `spec.certificates` MUST include `network/${SECRET_DOMAIN/./-}-production-tls`.
  - `spec.identityProvider.provider` MUST be `google` referencing `pomerium/google-idp`.
  - `spec.secrets` MUST reference `pomerium/bootstrap` (created by `pomerium-gen-secrets`).
  - `spec.storage.file.path` MUST be `/var/lib/pomerium` matching the `pomerium-data` PVC mount in `Deployment/pomerium`.

## SOPS Encryption Rules (`.sops.yaml`)

- `kubernetes/workloads/network/pomerium/ingresses\.sops\.ya?ml` MUST encrypt `^(ingress\.pomerium\.io/policy)$`.
- `kubernetes/workloads/network/pomerium/google-idp-secret\.sops\.ya?ml` is covered by `(bootstrap|kubernetes)/.*\.sops\.ya?ml` encrypting `^(data|stringData)$`.
