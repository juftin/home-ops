# SecurityPolicy Change Playbook

Use this playbook for safe updates to OAuth allowlists and policy settings.

______________________________________________________________________

## Scope

Primary files:

- `kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml`
- `kubernetes/apps/network/envoy-gateway/app/oauth-policy-internal.sops.yaml`

Related secret:

- `kubernetes/apps/network/envoy-gateway/app/oauth-client-secret.sops.yaml`

______________________________________________________________________

## Standard Change Procedure

## 1) Decrypt

```bash
sops --decrypt kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml > /tmp/oauth-policy.yaml
```

## 2) Edit

- Keep `authorization.defaultAction: Deny`
- Keep `email_verified=true` check
- Add/remove only lowercase emails in `email` claim values

## 3) Re-encrypt and clean up

```bash
sops --encrypt /tmp/oauth-policy.yaml > kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml
rm /tmp/oauth-policy.yaml
```

## 4) Validate and apply via GitOps

```bash
task lint
task dev:validate
git add kubernetes/apps/network/envoy-gateway/app/oauth-policy.sops.yaml
git commit -m "🔐 update oauth allowlist"
git push
```

______________________________________________________________________

## Rollback Procedure

If behavior regresses after a policy change:

1. Revert the commit that touched the policy file
2. Push the revert
3. Confirm reconciliation and access behavior

```bash
git revert <bad-commit-sha>
git push
```

______________________________________________________________________

## Emergency Revoke Procedure

When immediate access revocation is required:

1. Remove affected email(s) from allowlist and push
2. Restart Envoy Gateway pods to invalidate active sessions quickly

```bash
kubectl rollout restart deployment -n network -l app.kubernetes.io/name=envoy-gateway
```

______________________________________________________________________

## Safety Checks Before Merge

- [ ] No plaintext secrets or emails committed outside encrypted fields
- [ ] Policy file still SOPS-encrypted (`ENC[AES256` present)
- [ ] `targetRefs` still point at intended Gateway
- [ ] Redirect URLs still match gateway hostname
- [ ] Branch test completed and `task dev:stop` run
