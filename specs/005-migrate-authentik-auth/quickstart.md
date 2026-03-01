# Quickstart: Envoy Authentik Authentication Migration

## Prerequisites

- Working branch: `005-migrate-authentik-auth`
- Local prerequisites configured (`age.key`, `kubeconfig`, toolchain)
- Ability to run repository task targets

## 1) Edit manifests for Authentik-mode support

1. Update Envoy gateway auth resources to support external authorization flow through Authentik.
2. Preserve legacy auth configuration path for cluster-wide rollback.
3. Ensure protected routes continue to express auth intent without per-route mode branching.

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

If issues occur, switch cluster-wide mode back to `legacy` and reconcile; if urgent, revert the feature commit and reconcile back to known-good behavior.
