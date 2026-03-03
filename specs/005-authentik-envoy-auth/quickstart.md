# Quickstart: Authentik Cluster Authentication (Phased)

## Prerequisites

1. Confirm you are on branch `005-authentik-envoy-auth`.
2. Confirm bootstrap inputs exist before first install:
   - `authentik-bootstrap` ExternalSecret source in 1Password.
   - `authentik-secret-key` ExternalSecret source in 1Password.
   - Envoy OIDC secret (`oauth-client-secret`) includes an Authentik client secret value.
3. Confirm Cloudflare tunnel and DNS host coverage includes `auth.${SECRET_DOMAIN}`, `oauth.${SECRET_DOMAIN}`, and pilot app hosts.
4. Confirm Flux applies `authentik-envoy-provider-blueprint` in `security` so Authentik provider/app objects are reconciled declaratively.

## Rollout

1. Deploy Authentik manifests under `kubernetes/apps/security/authentik/`.
2. Migrate pilot routes (`grafana`, `headlamp`) to auth path `authentik`.
3. Keep non-pilot routes assigned to `google-proxy` in `files/auth-path-matrix.yaml`.
4. Ensure protected routes without auth-path assignment are denied.

## Mixed auth-path rollback guidance

1. If pilot login fails, move affected pilot route assignment back to `google-proxy` in `files/auth-path-matrix.yaml`.
2. Keep wildcard traffic pointed at `envoy-external` while only explicit pilot hosts use `envoy-oauth`.
3. Reconcile and re-test route-by-route before re-enabling `authentik` assignment.

## 30-day auth outcome query procedure

1. Query Envoy auth logs/metrics by fields `routeId`, `authPath`, `outcome`, and `occurredAt`.
2. Scope investigations to `occurredAt >= now()-30d`.
3. Validate both allowed and denied outcomes for each migrated route.

## Validation

- `task lint` → passed
- `task dev:validate` → passed (43 tests)
