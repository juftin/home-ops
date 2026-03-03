# Quickstart: Authentik Cluster Authentication (Phased)

1. Confirm you are on branch `005-authentik-envoy-auth`.
2. Deploy Authentik manifests under `kubernetes/apps/security/authentik/` and confirm required bootstrap secrets are available via encrypted or external secret references.
3. Select the initial pilot subset of protected routes for Authentik migration.
4. Update route auth-path assignments for pilot routes to `authentik` and keep non-pilot routes on `google-proxy`.
5. Ensure explicit callback/host routing remains configured for auth flows and that wildcard-only ingress does not handle callbacks.
6. Confirm protected routes without assignment are denied by configuration.
7. Validate outcome records contain route, auth path, outcome, and timestamp and are queryable for at least 30 days.
8. Run local validation:
   - `task lint`
   - `task dev:validate`
9. For branch-cluster verification, use:
   - `task dev:start`
   - `task dev:sync` (for additional changes)
   - `task dev:stop` (always restore cluster tracking)
