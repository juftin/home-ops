# SecurityPolicy / Access Group Change Playbook

Use this playbook for safe updates to Pomerium `Admins` and `Users` email allowlists.

______________________________________________________________________

## Scope

Primary files:

- `kubernetes/workloads/network/pomerium/ingresses.sops.yaml`
  - `kind: List` of Pomerium `Ingress` resources using `&admins` and `&users` YAML anchors in
    `ingress.pomerium.io/policy` annotations
  - Encrypted via `.sops.yaml` rule matching `^(ingress\.pomerium\.io/policy)$`

Related secret:

- `kubernetes/workloads/network/pomerium/google-idp-secret.sops.yaml`

______________________________________________________________________

## Standard Change Procedure

## 1) Decrypt

```bash
sops --decrypt kubernetes/workloads/network/pomerium/ingresses.sops.yaml > /tmp/ingresses.yaml
```

## 2) Edit

- Keep all email addresses lowercase (`email.is: user@example.com`)
- Maintain two external access tiers:
  - `Admins` (`agentsview`, `paseo`, `herdr`, `hermes-agent`, `openclaw`, `argocd`)
  - `Users` (`grafana`; include admin emails in the users list as well)
- Note: SOPS expands YAML anchors during encryption, so update all `Admins` entries (or restore
  `&admins` / `*admins` anchors in `/tmp/ingresses.yaml` before re-encrypting) so every admin
  route stays synchronized.

## 3) Re-encrypt and clean up

```bash
sops --filename-override kubernetes/workloads/network/pomerium/ingresses.sops.yaml \
  --encrypt /tmp/ingresses.yaml > kubernetes/workloads/network/pomerium/ingresses.sops.yaml
rm /tmp/ingresses.yaml
```

## 4) Validate and apply via GitOps

```bash
task lint
task dev:validate
git add kubernetes/workloads/network/pomerium/ingresses.sops.yaml
git commit -m "🔐 update pomerium allowlist"
git push
```

______________________________________________________________________

## Rollback Procedure

```bash
git revert <bad-commit-sha>
git push
```

______________________________________________________________________

## Emergency Revoke Procedure

1. Remove affected email(s) from `ingresses.sops.yaml`, re-encrypt, and push
2. Restart Pomerium to invalidate cached state if needed:

```bash
kubectl rollout restart deployment -n pomerium pomerium
```

______________________________________________________________________

## Safety Checks Before Merge

- [ ] No plaintext email addresses or secrets committed outside encrypted fields
- [ ] Policy file still SOPS-encrypted (`ENC[AES256_GCM` present)
- [ ] All admin `Ingress` items share identical `Admins` allowlists
- [ ] `Users` allowlist (`grafana`) includes `Admins` emails
- [ ] Branch test completed and `task dev:stop` run
