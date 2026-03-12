# Quickstart: Headlamp Token Sync Reliability

## Goal

Validate that Headlamp login decisions stay aligned with the currently authoritative token value and
that drift is visible to operators quickly.

## Prerequisites

- Repository prepared with required local files (`age.key`, `kubeconfig`)
- Working branch: `001-fix-headlamp-token-sync`
- Access to update the 1Password item used by `headlamp-admin-token`

## Step 1: Confirm baseline resources

```bash
kubectl get externalsecret -n observability headlamp-admin-token
kubectl get secret -n observability headlamp-admin-token
kubectl get httproute -n observability headlamp
kubectl get securitypolicy -n network envoy-oauth-policy envoy-oauth-internal-policy
```

Expected:

- ExternalSecret is present and ready
- Target secret exists
- Headlamp route is attached to `envoy-oauth`
- OAuth policies are present

## Step 2: Run repository validation gates

```bash
task lint
task dev:validate
```

Expected:

- Linting/formats are clean
- Flux-local render passes

## Step 2a: Foundational token sync checks

```bash
kubectl get configmap -n observability headlamp-token-sync-config headlamp-token-sync-state
kubectl get sa,role,rolebinding -n observability | grep headlamp-token-sync-check
kubectl get cronjob -n observability headlamp-token-sync-check
```

Expected:

- Token precedence config exists
- Sync-check RBAC objects are present
- CronJob is scheduled every minute

## Step 3: Exercise rotation and propagation behavior

1. Rotate the Headlamp admin token in 1Password.
2. Wait for ExternalSecret reconciliation (or trigger reconciliation if your workflow allows).
3. Confirm the in-cluster secret changed and a new login path uses the rotated value.

Verification commands:

```bash
kubectl describe externalsecret -n observability headlamp-admin-token
kubectl get secret -n observability headlamp-admin-token -o yaml
```

Expected:

- Secret sync succeeds
- New auth decisions align with the rotated value within the 5-minute objective
- `secret.reloader.stakater.com/reload` annotation includes `headlamp-admin-token`

## Step 4: Validate conflict visibility

Simulate a mismatch condition (for example, stale runtime behavior after rotation) and verify:

- Sync state reports `out_of_sync` or `degraded`
- Incident record includes reason and affected decisions
- User-facing failure is actionable (retry or operator follow-up guidance)

Verification commands:

```bash
kubectl get configmap -n observability headlamp-token-sync-state -o yaml
kubectl logs -n observability --tail=200 -l job-name=headlamp-token-sync-check
```

## Step 5: Operational checks for OAuth path

Use the existing OIDC runbook for end-to-end checks:

- `docs/OIDC-TROUBLESHOOTING.md`
- `docs/POST-MERGE-VERIFICATION.md`

Focus on callback health, deny behavior, and route integrity during token-change windows.

## Step 6: Verify status endpoints

Query through the OAuth-protected host:

```bash
curl -sS https://headlamp.${SECRET_DOMAIN}/token-sync/status
curl -sS https://headlamp.${SECRET_DOMAIN}/token-sync/sources
curl -sS https://headlamp.${SECRET_DOMAIN}/token-sync/incidents
```

Expected:

- Payloads conform to `contracts/token-sync.openapi.yaml`
- `state`, `authoritativeSource`, and incident list are present
- Response data updates after drift simulation and subsequent recovery

## Step 7: Branch testing workflow (if cluster testing is needed)

```bash
task dev:start
task dev:sync
task dev:stop
```

Always run `task dev:stop` to restore cluster tracking back to `main`.
