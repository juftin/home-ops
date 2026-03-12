# Quickstart: Envoy Authentik Authentication Migration

## Prerequisites

- Working branch: `005-migrate-authentik-auth`
- Local prerequisites configured (`age.key`, `kubeconfig`, toolchain)
- Ability to run repository task targets

## 1) Edit manifests for Authentik-mode support

1. Set cluster-wide auth mode in:
   - `kubernetes/apps/network/envoy-gateway/app/helmrelease.yaml`
   - `kubernetes/apps/network/envoy-gateway/app/envoy.yaml` (`ConfigMap/envoy-auth-mode`)
2. Update Envoy gateway auth resources so OAuth entrypoint routes through Authentik-managed gateways first.
3. Preserve legacy fallback by retaining legacy gateway + SecurityPolicy resources and mode annotations.
4. Ensure protected routes continue to express auth intent without per-route mode branching.

## 2) Validate locally

```bash
task lint
task dev:validate
```

## 3) Validate in branch test workflow

```bash
task dev:start
# verify protected route behavior for allow and deny cases
# verify mode switch legacy <-> authentik
# verify denied/logged-out utility routes remain reachable
# verify callback path /oauth2/callback is served by oauth gateway
task dev:stop
```

## 4) Verify observable outcomes

For allow and deny attempts, confirm auth outcomes expose:

- timestamp
- user identity
- protected route
- decision
- denial reason (for deny)

## 5) Rollback

If issues occur:

1. Switch cluster-wide mode back to `legacy` in the auth mode values/ConfigMap.
2. Reconcile and re-run the protected-route checks.
3. If urgent, revert the feature commit and reconcile back to known-good behavior.

## 6) Fail-closed outage validation

1. Temporarily block Authentik decision endpoint reachability from Envoy.
2. Attempt protected-route access as a previously authorized user.
3. Confirm request is denied (no fail-open behavior), and `/denied` route remains reachable.
4. Restore Authentik reachability and verify access returns for authorized users.
