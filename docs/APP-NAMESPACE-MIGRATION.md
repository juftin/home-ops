# App Namespace Migration

The applications `camply`, `echo`, `herdr`, `hermes-agent`, `lunchmoney`, `oauth-pages`, `openclaw`, and `paseo`
each run in a namespace matching their name. ArgoCD Application names, Helm release names,
Service names, and public hostnames stay the same. Camply's controllers stay together in
`camply`. The `default` namespace itself must remain.

Fresh installations can sync normally. Existing installations need a maintenance window
and the storage handoff below **before merging or testing the namespace move**. Namespace
changes create new resources; PVC contents do not move with the manifests. ArgoCD's
automated pruning can delete the old claims, and a PV with reclaim policy `Delete` can
then lose its backing data. See Kubernetes' [reclaim policy documentation](https://kubernetes.io/docs/tasks/administer-cluster/change-pv-reclaim-policy/).

## Persistent storage inventory

All source claims are in `default`; destination claims keep the same names.
Inventory the live bindings rather than guessing PV names.

| Destination namespace | PVC                      | Binding location                     |
| --------------------- | ------------------------ | ------------------------------------ |
| `camply`              | `camply-db-data`         | `pvc.yaml`: `spec.volumeName`        |
| `camply`              | `camply-valkey-data`     | `pvc.yaml`: `spec.volumeName`        |
| `camply`              | `camply-prometheus-data` | `pvc.yaml`: `spec.volumeName`        |
| `herdr`               | `herdr-home`             | `persistence.home.volumeName`        |
| `herdr`               | `herdr-workspace`        | `persistence.workspace.volumeName`   |
| `hermes-agent`        | `hermes-agent`           | `persistence.data.volumeName`        |
| `lunchmoney`          | `lunchmoney-db-data`     | `persistence.db-data.volumeName`     |
| `lunchmoney`          | `lunchmoney-valkey-data` | `persistence.valkey-data.volumeName` |
| `openclaw`            | `openclaw`               | `persistence.home.volumeName`        |
| `paseo`               | `paseo-home`             | `persistence.home.volumeName`        |
| `paseo`               | `paseo-workspace`        | `persistence.workspace.volumeName`   |

```bash
kubectl get pvc -n default -o wide
kubectl get pv -o wide
```

Record each claim's `spec.volumeName`, storage class, size, and PV node affinity.
Take verified backups of the database and all persistent application data, including
Paseo's home and workspace. Keep backups outside the volumes being migrated; agent homes
contain credentials and need protected backup storage.

## Staged GitOps rollout

1. Before activating the namespace move, set **each bound PV** in the inventory to
   `Retain`. Verify every policy with `kubectl get pv`. This protects backing data if
   ArgoCD prunes the source claims:

   ```bash
   kubectl patch pv <pv-name> --type=merge -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
   ```

2. Use a preparatory Git commit against the old `default` layout to stop all
   application writers. For app-template apps, set every controller's `replicas: 0`,
   including Herdr, Hermes Agent, OpenClaw, Paseo, and Lunch Money's app, scheduler,
   db, and valkey controllers.

   Camply uses `camply-web`, not app-template. Add this temporary Kustomize override
   to Camply's `app/kustomization.yaml` to stop all seven Deployments and suspend the
   release migration Job (which can also write to the database):

   ```yaml
   replicas:
     - name: camply-frontend
       count: 0
     - name: camply-backend
       count: 0
     - name: camply-worker
       count: 0
     - name: camply-beat
       count: 0
     - name: camply-postgresql
       count: 0
     - name: camply-valkey
       count: 0
     - name: camply-prometheus
       count: 0
   patches:
     - target:
         group: batch
         version: v1
         kind: Job
         name: camply-migrate-.*
       patch: |-
         - op: add
           path: /spec/suspend
           value: true
   ```

   Sync through the branch testing workflow, verify all application and migration
   Job pods have terminated, and take a final consistent backup. Keep writers stopped
   throughout the handoff. Preserve the original replica settings for restoration.

3. In the namespace migration commit used for rollout, keep the shutdown overrides in place.
   For app-template apps, add `volumeName: <recorded-pv-name>` under each existing
   persistence key in `values.yaml`. For example, in Paseo's `values.yaml`:

   ```yaml
   persistence:
     home:
       volumeName: <old-paseo-home-pv>
     workspace:
       volumeName: <old-paseo-workspace-pv>
   ```

   For Camply, set `spec.volumeName: <recorded-pv-name>` on each of the three
   PVC documents in `kubernetes/workloads/apps/camply/pvc.yaml`, and confirm each
   has `metadata.namespace: camply`. Keep the chart's `existingClaim` values and
   the PVCs' `Prune=false`/`keep` annotations; Camply does not use app-template
   persistence keys.

   Add those fields to the existing entries, preserving their size, storage class,
   and mounts. Explicit volume names prevent fresh empty volumes from being provisioned.
   Run `task lint` and `task dev:validate`, then `task dev:sync`. ArgoCD creates the new
   namespaces and destination claims. Claims may remain Pending until the old bindings
   are released; keep replicas at zero.

4. For each recorded binding, confirm its PV still has `Retain`, that no old pod uses
   it, and that the destination claim requests that exact PV. If ArgoCD has not already
   pruned the source claim, delete that specific claim from `default` and wait for deletion.
   Camply source PVCs have `Prune=false` and require this explicit deletion.
   Once the PV is Released, remove its old claim reference:

   ```bash
   kubectl delete pvc -n default <claim-name> --wait=true
   kubectl patch pv <pv-name> --type=json -p='[{"op":"remove","path":"/spec/claimRef"}]'
   kubectl get pvc -n <app-namespace> <claim-name> -o wide
   ```

   Verify the new claim is Bound to the recorded PV and retains its node affinity.
   This follows Kubernetes' [manual PV reclamation model](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reclaiming).
   Do not delete the PV or change its backing path.

5. After all eleven claims are Bound correctly, remove Camply's temporary shutdown
   overrides (including Job suspension), restore the other original replica settings
   through Git and sync. Keep the explicit `volumeName` fields in the deployed manifests;
   removing an explicitly managed binding can attempt an immutable PVC update. Leave PVs on `Retain`
   until the migration and backups have been verified.

6. Confirm `agent-tools` ConfigMaps exist in `paseo`, `openclaw`, and `herdr` before
   starting agent pods. The `agent-tools` Application generates all three from the
   shared installer. Update any persisted OpenClaw Lunch Money URL to
   `http://lunchmoney-app.lunchmoney.svc.cluster.local:8000`. Its Cilium policy must
   select the `lunchmoney` namespace; Paseo's policy must select Tailscale proxies with
   `tailscale.com/parent-resource-ns: paseo`.

   Check ExternalSecrets in each app namespace, `tailscale-config` in `paseo` and `lunchmoney`, data
   contents, application health, HTTPRoute acceptance, OAuth callback/denied/logout
   behavior, and Paseo's Tailscale endpoint. Delete leftover old resources only after
   checking that the destinations work. Finish branch testing with `task dev:stop`.
   Returning to `main` before it contains the migration also requires returning storage
   to `default`; plan the merge and maintenance window together.

## Rollback

Stop writers through Git before reversing a handoff. Keep PVs on `Retain`, record their
current bindings, and use the same prebinding/release sequence to return claims to
`default`. A Git revert alone recreates resources but does not move persistent data back.
Reconcile the old layout only after its claims bind to the intended PVs. Restore backups
if integrity checks fail, then verify application access and finish with `task dev:stop`.
