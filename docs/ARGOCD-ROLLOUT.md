# ArgoCD Rollout Runbook

This runbook tracks the Flux-to-ArgoCD migration lifecycle.

______________________________________________________________________

## Scope

- Bootstrap ArgoCD control-plane resources.
- Migrate workloads in dependency-aware waves.
- Verify health, sync, drift, and ownership cutover.
- Execute ArgoCD-only rollback if a wave fails.

______________________________________________________________________

## Command Index

```bash
task dev:argocd:render
task dev:argocd:migrate-wave WAVE=<wave> NAMESPACE=<namespace>
task dev:argocd:verify-wave WAVE=<wave> NAMESPACE=<namespace>
task dev:argocd:verify-cutover
task dev:argocd:verify-health
task dev:argocd:rollback-wave WAVE=<wave> REASON="<reason>"
task dev:argocd:health
task dev:argocd:validate-rbac
```

______________________________________________________________________

## Rollback Drill (SC-004)

Use this sequence to validate restoration within 15 minutes:

1. Record start time in UTC.

2. Run:

   ```bash
   task dev:argocd:rollback-wave WAVE=<wave> REASON="rollback drill"
   ```

3. Verify ArgoCD control-plane health:

   ```bash
   task dev:argocd:health
   ```

4. Verify post-rollback wave status:

   ```bash
   task dev:argocd:verify-wave WAVE=<wave> NAMESPACE=<namespace>
   ```

5. Record completion time and calculate elapsed minutes.

Evidence to capture per drill:

- Trigger reason and wave ID.
- Start/end timestamps and elapsed duration.
- Verification command outputs.
- Follow-up actions (if any).

______________________________________________________________________

## Access Validation Procedure

Validate role-based policy after cutover:

1. Confirm policy object exists:

   ```bash
   task dev:argocd:validate-rbac
   ```

2. Confirm maintainers only have read visibility (no sync/override).

3. Confirm admins can sync and administer project resources.

4. Record identities tested and observed permissions in the rollout handoff.
