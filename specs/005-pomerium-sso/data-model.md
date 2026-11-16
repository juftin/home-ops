# Data Model: Replace Envoy OAuth with Pomerium SSO

## Entities & Configuration Schema

### 1. `Pomerium` Global Configuration (`ingress.pomerium.io/v1`)

| Field                            | Value                                             | Purpose                                                        |
| -------------------------------- | ------------------------------------------------- | -------------------------------------------------------------- |
| `metadata.name`                  | `global`                                          | Referenced by `--pomerium-config=global`                       |
| `metadata.namespace`             | `pomerium`                                        | Pomerium control-plane namespace                               |
| `spec.authenticate.url`          | `https://oauth.${SECRET_DOMAIN}`                  | Unified Google OAuth callback endpoint                         |
| `spec.certificates`              | `["network/${SECRET_DOMAIN/./-}-production-tls"]` | Wildcard TLS cert for `*.${SECRET_DOMAIN}`                     |
| `spec.cookie.domain`             | `${SECRET_DOMAIN}`                                | Shared root cookie domain                                      |
| `spec.identityProvider.provider` | `google`                                          | Google OIDC provider                                           |
| `spec.identityProvider.secret`   | `pomerium/google-idp`                             | SOPS Secret with `client_id` & `client_secret`                 |
| `spec.identityProvider.scopes`   | `["openid", "profile", "email"]`                  | Standard Google OIDC email claims                              |
| `spec.secrets`                   | `pomerium/bootstrap`                              | Auto-generated `shared_secret`, `cookie_secret`, `signing_key` |
| `spec.storage.file.path`         | `/var/lib/pomerium`                               | Persistent databroker storage on `node-local` PVC              |

### 2. Google IdP Secret (`google-idp-secret.sops.yaml`)

- **Kind**: `Secret` (`Opaque`), `metadata.name: google-idp`, `metadata.namespace: pomerium`
- **Encrypted fields** (`.sops.yaml` `^(data|stringData)$`):
  - `stringData.client_id`: Google OAuth 2.0 Client ID
  - `stringData.client_secret`: Google OAuth 2.0 Client Secret

### 3. Protected Application Ingresses (`ingresses.sops.yaml`)

A Kubernetes `List` (`apiVersion: v1`, `kind: List`) containing 7 `networking.k8s.io/v1` `Ingress` items (`ingressClassName: pomerium`), with `ingress.pomerium.io/policy` SOPS-encrypted via `.sops.yaml` (`^(ingress\.pomerium\.io/policy)$`).

| Ingress Name   | Namespace       | Hostname                      | Upstream Service & Port(s)                               | WebSockets | Access Group Anchor |
| -------------- | --------------- | ----------------------------- | -------------------------------------------------------- | ---------- | ------------------- |
| `agentsview`   | `agentsview`    | `agentsview.${SECRET_DOMAIN}` | `agentsview-app:8080`                                    | `false`    | `*admins`           |
| `paseo`        | `paseo`         | `paseo.${SECRET_DOMAIN}`      | `paseo:6767`                                             | `true`     | `*admins`           |
| `herdr`        | `herdr`         | `herdr.${SECRET_DOMAIN}`      | `herdr:7317`                                             | `true`     | `*admins`           |
| `hermes-agent` | `hermes-agent`  | `hermes.${SECRET_DOMAIN}`     | `/v1` -> `hermes-agent:8642`, `/` -> `hermes-agent:9119` | `true`     | `*admins`           |
| `openclaw`     | `openclaw`      | `openclaw.${SECRET_DOMAIN}`   | `openclaw:18789`                                         | `true`     | `*admins`           |
| `argocd`       | `argocd`        | `argocd.${SECRET_DOMAIN}`     | `argocd-server:80`                                       | `true`     | `*admins`           |
| `grafana`      | `observability` | `grafana.${SECRET_DOMAIN}`    | `kube-prometheus-stack-grafana:80`                       | `true`     | `*users`            |

### 4. PPL Policy Structure (YAML Anchors)

```yaml
# Admins anchor (&admins):
allow:
  or:
    - email:
        is: admin@example.com

# Users anchor (&users): includes all admin emails plus non-admin user emails
allow:
  or:
    - email:
        is: admin@example.com
    - email:
        is: user@example.com
```
