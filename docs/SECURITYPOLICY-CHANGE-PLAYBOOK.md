# SecurityPolicy / Access Group Change Playbook

Use this playbook for safe updates to Pomerium `Admins` and `Users` email allowlists.

______________________________________________________________________

## Scope

Primary files:

- `kubernetes/workloads/network/pomerium/groups.sops.yaml`
  - `local-config` ConfigMap encrypting `data.admins` and `data.users` once via SOPS
- `kubernetes/workloads/network/pomerium/ingresses.yaml`
  - Plaintext `Ingress` definitions labeled `pomerium.io/group: admins` or `pomerium.io/group: users`
  - `kubernetes/workloads/network/pomerium/kustomization.yaml` injects `data.admins` / `data.users`
    into `ingress.pomerium.io/policy` at render time via Kustomize `replacements`

Related secret:

- `kubernetes/workloads/network/pomerium/google-idp-secret.sops.yaml`

______________________________________________________________________

## Standard Change Procedure

## 1) Decrypt

```bash
sops --decrypt kubernetes/workloads/network/pomerium/groups.sops.yaml > /tmp/groups.yaml
```

## 2) Edit

- Keep all email addresses lowercase (`email.is: user@example.com`)
- Maintain two external access tiers:
  - `data.admins` (`agentsview`, `paseo`, `herdr`, `hermes-agent`, `openclaw`, `argocd`)
  - `data.users` (`grafana`; include admin emails in the users list as well)

## 3) Re-encrypt and clean up

```bash
sops --filename-override kubernetes/workloads/network/pomerium/groups.sops.yaml \
  --encrypt /tmp/groups.yaml > kubernetes/workloads/network/pomerium/groups.sops.yaml
rm /tmp/groups.yaml
```

## 4) Validate and apply via GitOps

```bash
task lint
task dev:validate
git add kubernetes/workloads/network/pomerium/groups.sops.yaml
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

1. Remove affected email(s) from `groups.sops.yaml`, re-encrypt, and push
2. Restart Pomerium to invalidate cached state if needed:

```bash
kubectl rollout restart deployment -n pomerium pomerium
```

______________________________________________________________________

## Safety Checks Before Merge

- [ ] No plaintext email addresses or secrets committed outside encrypted fields
- [ ] `groups.sops.yaml` still SOPS-encrypted (`ENC[AES256_GCM` present under `data`)
- [ ] `data.users` includes `data.admins` emails
- [ ] Branch test completed and `task dev:stop` run
