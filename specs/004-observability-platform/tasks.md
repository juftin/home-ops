# Tasks: Observability Platform

**Input**: Design documents from `/specs/004-observability-platform/`
**Prerequisites**: plan.md ✅ spec.md ✅ research.md ✅ data-model.md ✅ contracts/ ✅ quickstart.md ✅

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.
Tests are not included (none requested in spec).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1–US4)
- Exact file paths are included in all task descriptions

______________________________________________________________________

## Phase 1: Setup

**Purpose**: Verify external dependencies and provision required secrets before any manifests are
written. These must be done first — a bad OCI URL or missing 1Password item will cause Flux
reconciliation to silently fail.

- [ ] T001 Verify OCI chart URLs exist in the home-operations mirror by running:
  `crane ls ghcr.io/home-operations/charts-mirror/kube-prometheus-stack`,
  `crane ls ghcr.io/home-operations/charts-mirror/loki`, and
  `crane ls ghcr.io/home-operations/charts-mirror/alloy`.
  If any URL returns an error, fall back to the upstream registry (documented in
  `specs/004-observability-platform/research.md` Decision 7). Record the verified URLs and latest
  tag for each chart — these will be used in all ocirepository.yaml files.

- [ ] T002 [P] Create a 1Password item named `grafana-admin-creds` in the vault used by this
  cluster's ExternalSecret ClusterSecretStore. The item MUST have two fields: `username` (set to
  `admin`) and `password` (set to a strong random value). Confirm the item is accessible by the
  external-secrets operator: `kubectl get clustersecretstore onepassword -o jsonpath='{.status}'`.

- [ ] T003 [P] Create a 1Password item named `alertmanager-slack-webhook` in the same vault.
  The item MUST have one field: `webhook-url` containing a valid Slack incoming webhook URL
  (format: `https://hooks.slack.com/services/...`). Create the Slack webhook at
  api.slack.com/apps if one does not yet exist, pointing at your `#alerts` channel.

**Checkpoint**: OCI URLs verified and recorded. Both 1Password items exist and are readable by
the operator.

______________________________________________________________________

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the shared namespace kustomization entry point and confirm the existing
cluster prerequisites listed in `specs/004-observability-platform/quickstart.md` are satisfied.
This phase does not deploy anything — it confirms the environment is ready.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T004 Confirm cluster prerequisites are met by running the checks in
  `specs/004-observability-platform/quickstart.md` (Prerequisites section):
  `kubectl get ns observability`,
  `kubectl get gateway -n network envoy-external`,
  `kubectl get sc` (default storage class must exist),
  `kubectl get clustersecretstore onepassword`.
  Document any failures and resolve before proceeding.

- [x] T005 Review `kubernetes/apps/observability/kustomization.yaml` to understand its current
  structure (it currently lists only `headlamp/ks.yaml`). Do not modify it yet — each user story
  phase will add its own `resources:` entry as the final step of that phase, keeping changes
  atomic and independently revertible.

**Checkpoint**: All cluster prerequisites confirmed. Environment is ready for user story
implementation.

______________________________________________________________________

## Phase 3: User Story 1 — Cluster Health at a Glance (Priority: P1) 🎯 MVP

**Goal**: Deploy kube-prometheus-stack with Prometheus, Grafana, node-exporter, and
kube-state-metrics. Grafana is exposed via HTTPS at `grafana.${SECRET_DOMAIN}` with pre-built
dashboards available on first login. Prometheus metrics are stored on a 30Gi node-local PVC
with 30-day retention.

**Independent Test**: Navigate to `https://grafana.juftin.dev`, log in, open any dashboard in
"Kubernetes / Compute Resources" folder — panels must populate without manual configuration.
Run `up` query in Grafana Explore → all targets return `1`.

### Implementation for User Story 1

- [x] T006 [US1] Create directory `kubernetes/apps/observability/kube-prometheus-stack/app/`.
  Create `kubernetes/apps/observability/kube-prometheus-stack/ks.yaml` following the headlamp
  pattern (`kubernetes/apps/observability/headlamp/ks.yaml`). Set `name: kube-prometheus-stack`,
  `namespace: observability`, `path: ./kubernetes/apps/observability/kube-prometheus-stack/app`,
  `targetNamespace: observability`. Add `postBuild.substituteFrom` referencing `cluster-secrets`
  Secret (same pattern as headlamp). Set `timeout: 15m` and `wait: true` (CRDs must be ready
  before Loki/Alloy can deploy).

- [x] T007 [P] [US1] Create `kubernetes/apps/observability/kube-prometheus-stack/app/ocirepository.yaml`.
  Use the verified URL from T001 (expected:
  `oci://ghcr.io/home-operations/charts-mirror/kube-prometheus-stack`). Follow the headlamp
  OCIRepository pattern (`kubernetes/apps/observability/headlamp/app/helmrelease.yaml` top
  section). Set `interval: 5m`, `layerSelector.mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip`,
  `layerSelector.operation: copy`. Use the latest tag verified in T001.

- [x] T008 [P] [US1] Create `kubernetes/apps/observability/kube-prometheus-stack/app/externalsecret.yaml`.
  Target secret name: `grafana-admin-creds`. Reference ClusterSecretStore `onepassword`.
  Use `dataFrom[0].extract.key: grafana-admin-creds` (matching the 1Password item created in T002).
  Use the headlamp ExternalSecret (`kubernetes/apps/observability/headlamp/app/externalsecret.yaml`)
  as the exact pattern to follow.

- [x] T009 [P] [US1] Create `kubernetes/apps/observability/kube-prometheus-stack/app/httproute.yaml`.
  Hostname: `grafana.${SECRET_DOMAIN}`. Gateway: `envoy-external` in namespace `network`,
  section `https`. Backend: service `kube-prometheus-stack-grafana` port `80` in namespace
  `observability`. Follow the headlamp HTTPRoute pattern exactly
  (`kubernetes/apps/observability/headlamp/app/httproute.yaml`).

- [x] T010 [US1] Create `kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml`.
  Reference the OCIRepository created in T007. This is the primary configuration task — include
  all of the following values sections:

  - `fullnameOverride: kube-prometheus-stack`
  - `prometheus.prometheusSpec.scrapeInterval: 30s`
  - `prometheus.prometheusSpec.retention: 30d`
  - `prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.accessModes: [ReadWriteOnce]`
  - `prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage: 30Gi`
  - `prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues: false`
  - `prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues: false`
  - `prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues: false`
  - `grafana.enabled: true`
  - `grafana.adminUser` and `grafana.adminPassword` sourced from the `grafana-admin-creds` Secret
    (use `grafana.admin.existingSecret: grafana-admin-creds` with `adminUser` and `adminPassword` keys)
  - `grafana.sidecar.dashboards.enabled: true` (enables ConfigMap dashboard provisioning)
  - `grafana.sidecar.dashboards.searchNamespace: ALL`
  - Loki data source placeholder (leave commented for now — T027 in Phase 5 will add it)
  - `alertmanager.enabled: false` (Alertmanager is configured in Phase 4 / US2)
  - `nodeExporter.enabled: true`
  - `kubeStateMetrics.enabled: true`
  - Set `install.remediation.retries: -1` and `upgrade.cleanupOnFail: true` following headlamp pattern.

- [x] T011 [US1] Create `kubernetes/apps/observability/kube-prometheus-stack/app/kustomization.yaml`.
  List all resources created in T007–T010: `ocirepository.yaml`, `externalsecret.yaml`,
  `httproute.yaml`, `helmrelease.yaml`. Add schema comment header following headlamp pattern.

- [x] T012 [US1] Add `- ./kube-prometheus-stack/ks.yaml` to the `resources:` list in
  `kubernetes/apps/observability/kustomization.yaml`. This is the change that causes Flux to
  begin reconciling the kube-prometheus-stack Kustomization.

- [ ] T013 [US1] Run `task lint` to auto-fix YAML formatting, then `task dev:validate` to
  render all HelmReleases offline. Fix any validation errors before committing. Confirm
  kube-prometheus-stack HelmRelease renders cleanly with no missing value references.

**Checkpoint**: User Story 1 is complete when `task dev:validate` passes. Deploy with
`task dev:start`, then follow verification steps 1–4 in
`specs/004-observability-platform/quickstart.md` to validate dashboards load and all scrape
targets show `up=1`.

______________________________________________________________________

## Phase 4: User Story 2 — Alerting on Cluster Issues (Priority: P2)

**Goal**: Enable Alertmanager with a Slack receiver so that alerts for disk pressure,
crash-looping pods, and node issues fire to Slack within 3 minutes. Alert resolution also
sends a Slack notification.

**Independent Test**: Use the manual test procedure in
`specs/004-observability-platform/quickstart.md` (Verification Step 6) — add a test alert via
`amtool`, confirm it appears in Slack within 3 minutes, confirm a resolved notification follows.

### Implementation for User Story 2

- [x] T014 [US2] Update `kubernetes/apps/observability/kube-prometheus-stack/app/externalsecret.yaml`
  to add a second data source: `dataFrom[1].extract.key: alertmanager-slack-webhook` targeting
  a second Secret named `alertmanager-slack-webhook` (keep `grafana-admin-creds` as `dataFrom[0]`).
  Alternatively, create a second ExternalSecret resource in the same file or a new
  `externalsecret-alertmanager.yaml` listed in the kustomization — either is valid; choose the
  cleaner approach.

- [x] T015 [US2] Update `kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml`
  to enable and configure Alertmanager:

  - Change `alertmanager.enabled: true`
  - Add `alertmanager.alertmanagerSpec.alertmanagerConfiguration` OR use
    `alertmanager.config` inline values block with:
    - `global.slack_api_url` sourced from the `alertmanager-slack-webhook` Secret
      (use `alertmanager.alertmanagerSpec.secrets: [alertmanager-slack-webhook]` to mount the
      secret, then reference `$slack_api_url` from the mounted file, or use the
      `alertmanager.config.global.slack_api_url` with a Secret value reference)
    - Receiver named `slack` with `slack_configs[0].channel: '#alerts'`,
      `send_resolved: true`
    - Route: `receiver: slack`, `group_wait: 30s`, `group_interval: 5m`,
      `repeat_interval: 4h`
  - Keep all other existing values intact.

- [ ] T016 [US2] Run `task lint` then `task dev:validate`. Confirm Alertmanager is included in
  the rendered HelmRelease output. Fix any YAML structure errors in the Alertmanager config
  block before committing.

**Checkpoint**: User Story 2 is complete when `task dev:validate` passes. During live testing
(`task dev:sync`), verify Alertmanager pod is running and the manual test alert in quickstart.md
Step 6 delivers to Slack.

______________________________________________________________________

## Phase 5: User Story 3 — Log Exploration (Priority: P3)

**Goal**: Deploy Loki (log storage) and Alloy (log shipper DaemonSet) so that all pod logs are
queryable in Grafana's Explore view by namespace, pod, label, and free-text. Configure Grafana's
Loki data source so metric-to-log navigation works.

**Independent Test**: In Grafana → Explore → Loki data source, query
`{namespace="observability"} | limit 20` — must return log lines with timestamps and pod labels.
Navigate from a Grafana panel to Explore in context — Loki must pre-filter to the correct pod
and time range.

### Implementation for User Story 3

- [x] T017 [US3] Create directory `kubernetes/apps/observability/loki/app/`.
  Create `kubernetes/apps/observability/loki/ks.yaml` following the kube-prometheus-stack ks.yaml
  pattern (T006). Set `name: loki`, `namespace: observability`,
  `path: ./kubernetes/apps/observability/loki/app`. Add
  `dependsOn: [{name: kube-prometheus-stack, namespace: observability}]` so Loki waits for the
  Prometheus Operator CRDs to be installed before reconciling. Set `timeout: 10m`, `wait: true`.

- [x] T018 [P] [US3] Create `kubernetes/apps/observability/loki/app/ocirepository.yaml`.
  Use the verified Loki OCI URL from T001 (expected:
  `oci://ghcr.io/home-operations/charts-mirror/loki`). Follow the same OCIRepository pattern
  as T007. Use the latest tag verified in T001.

- [x] T019 [US3] Create `kubernetes/apps/observability/loki/app/helmrelease.yaml`.
  Reference the Loki OCIRepository from T018. Configure single-binary mode with filesystem
  backend and node-local PVC:

  - `loki.commonConfig.replication_factor: 1`
  - `loki.schemaConfig` with appropriate schema version
  - `loki.storage.type: filesystem`
  - `loki.limits_config.retention_period: 168h` (7 days)
  - `loki.compactor.retention_enabled: true`
  - `singleBinary.replicas: 1`
  - `singleBinary.persistence.enabled: true`
  - `singleBinary.persistence.size: 10Gi`
  - `singleBinary.persistence.storageClass: ""` (use cluster default)
  - `gateway.enabled: false` (not needed for single-binary homelab)
  - `test.enabled: false`
  - `monitoring.selfMonitoring.enabled: false` (avoids circular dependency)
  - `monitoring.serviceMonitor.enabled: true` (for Prometheus scraping)
    Set `install.remediation.retries: -1` and `upgrade.cleanupOnFail: true`.

- [x] T020 [US3] Create `kubernetes/apps/observability/loki/app/kustomization.yaml`.
  List resources: `ocirepository.yaml`, `helmrelease.yaml`.

- [x] T021 [US3] Create directory `kubernetes/apps/observability/alloy/app/`.
  Create `kubernetes/apps/observability/alloy/ks.yaml`. Set `name: alloy`,
  `namespace: observability`, `path: ./kubernetes/apps/observability/alloy/app`. Add
  `dependsOn: [{name: loki, namespace: observability}]` so Alloy waits for Loki's endpoint
  to be available. Set `timeout: 5m`, `wait: false`.

- [x] T022 [P] [US3] Create `kubernetes/apps/observability/alloy/app/ocirepository.yaml`.
  Use the verified Alloy OCI URL from T001 (expected:
  `oci://ghcr.io/home-operations/charts-mirror/alloy`). Follow the same OCIRepository pattern.

- [x] T023 [US3] Create `kubernetes/apps/observability/alloy/app/helmrelease.yaml`.
  Reference the Alloy OCIRepository from T022. Configure Alloy as a DaemonSet log shipper:

  - `alloy.configMap.content`: Alloy pipeline config that:
    - Uses `discovery.kubernetes` to discover all pods
    - Uses `loki.source.kubernetes` to tail pod logs from discovered pods
    - Applies relabeling to extract `namespace`, `pod`, `container`, `node_name`, `app`
      labels per the schema in `specs/004-observability-platform/contracts/loki-label-schema.md`
    - Forwards to `loki.write` pointing at
      `http://loki.observability.svc.cluster.local:3100/loki/api/v1/push`
  - `controller.type: daemonset`
  - `tolerations`: add toleration for control-plane nodes so logs are collected from all nodes
    Set `install.remediation.retries: -1` and `upgrade.cleanupOnFail: true`.

- [x] T024 [US3] Create `kubernetes/apps/observability/alloy/app/kustomization.yaml`.
  List resources: `ocirepository.yaml`, `helmrelease.yaml`.

- [x] T025 [US3] Update `kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml`
  to add the Loki data source to Grafana (as specified in
  `specs/004-observability-platform/data-model.md` — Entity: Dashboard, Loki data source
  wiring section). Add under `grafana.additionalDataSources`:

  ```yaml
    - name: Loki
      type: loki
      url: http://loki.observability.svc.cluster.local:3100
      access: proxy
      isDefault: false
  ```

  This satisfies FR-009 (metric-to-log navigation) and is required for SC-007.

- [x] T026 [US3] Add `- ./loki/ks.yaml` and `- ./alloy/ks.yaml` to the `resources:` list in
  `kubernetes/apps/observability/kustomization.yaml`. Both entries must be added atomically in
  the same commit alongside the loki/ and alloy/ directories.

- [ ] T027 [US3] Run `task lint` then `task dev:validate`. Confirm Loki and Alloy HelmReleases
  render cleanly. Confirm the Loki data source is present in the kube-prometheus-stack render.
  Fix any config errors in the Alloy pipeline config or Loki schema config.

**Checkpoint**: User Story 3 is complete when `task dev:validate` passes. During live testing,
run verification steps 5 in `specs/004-observability-platform/quickstart.md` (Loki log query)
and confirm metric-to-log navigation works from any Grafana panel.

______________________________________________________________________

## Phase 6: User Story 4 — Persistent Storage Verification (Priority: P4)

**Goal**: Confirm that metrics and log data survive pod restarts and reboots. No new manifests
are created in this phase — it is a validation checkpoint for the PVC configuration established
in US1 (T010) and US3 (T019).

**Independent Test**: Restart the Prometheus StatefulSet pod; after it recovers, Grafana
dashboards must show historical data from before the restart with no gaps beyond the downtime.
Repeat for Loki.

### Implementation for User Story 4

- [ ] T028 [US4] During live cluster testing (`task dev:sync` in the feature branch), verify
  PVCs were created with the correct sizes:
  `kubectl get pvc -n observability`. Confirm two PVCs exist (Prometheus ~30Gi, Loki ~10Gi)
  and are in `Bound` state. Record the actual PVC names (derived from HelmRelease names) and
  update `specs/004-observability-platform/data-model.md` PVC Summary table with the real names.

- [ ] T029 [US4] Simulate a Prometheus pod restart and verify persistence:
  `kubectl rollout restart statefulset -n observability prometheus-kube-prometheus-stack-prometheus`
  Wait for the pod to recover, then open Grafana and confirm historical data from before the
  restart is visible. Document result in a comment or PR description.

- [ ] T030 [US4] Simulate a Loki pod restart and verify log persistence:
  `kubectl rollout restart statefulset -n observability loki`
  After recovery, query `{namespace="observability"}` in Grafana Explore — historical logs from
  before the restart must still be present. Document result.

**Checkpoint**: User Story 4 is complete when both PVCs are bound and data survives restarts.
Run `task dev:stop` after live testing to restore the cluster to `main`.

______________________________________________________________________

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation updates and final validation required before PR.

- [x] T031 [P] Update `README.md` — add Grafana, Prometheus, Alertmanager, Loki, and Alloy to
  the Apps or Components section. Follow the existing table/list format in the file. Include
  the Grafana URL (`grafana.juftin.dev`) and a one-line description for each component.

- [x] T032 [P] Update `docs/ARCHITECTURE.md` — add all five new components to the `observability`
  namespace entry in the namespaces table. Update any layer descriptions that reference the
  observability namespace. Remove or update the current single-entry description
  ("headlamp Kubernetes dashboard with Flux plugin") to reflect the full stack.

- [x] T033 Run `task lint` for a final formatting pass (run twice if needed — second run should
  always be clean). Confirm all five new files (ocirepository, helmrelease, ks.yaml, etc.) pass
  yamlfmt formatting.

- [ ] T034 Run `task dev:validate` one final time on the complete set of changes. Confirm all
  three HelmReleases (kube-prometheus-stack, loki, alloy) and all three Kustomizations render
  without errors.

- [ ] T035 Open a pull request from `004-observability-platform` to `main`. PR description must
  include: summary of changes, link to `specs/004-observability-platform/spec.md`, list of
  1Password items that must exist before merge, and the storage limitation note (node-local PVCs,
  data lost on permanent node failure).

______________________________________________________________________

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (OCI URLs must be verified first)
- **US1 (Phase 3)**: Depends on Phase 2 — kube-prometheus-stack is the core MVP
- **US2 (Phase 4)**: Depends on US1 (modifies the same HelmRelease)
- **US3 (Phase 5)**: Depends on US1 (Grafana data source update) and Phase 2 (OCI URL for Loki/Alloy)
- **US4 (Phase 6)**: Depends on US1 + US3 (verifies PVCs from both)
- **Polish (Phase 7)**: Depends on all user story phases being complete

### User Story Dependencies

- **US1 (P1)**: Independent — can start immediately after Foundational phase
- **US2 (P2)**: Depends on US1 (shares kube-prometheus-stack HelmRelease file)
- **US3 (P3)**: Partially parallel with US2 (different files: loki/, alloy/); T025 modifies
  kube-prometheus-stack HelmRelease so coordinate with US2 work on that file
- **US4 (P4)**: Validation only — runs after US1 and US3 are deployed to live cluster

### Within Each Phase

- All [P]-marked tasks within a phase can be written in parallel (different files, no conflicts)
- Non-[P] tasks must complete sequentially in the order listed
- `task lint` + `task dev:validate` (T013, T016, T027, T033–T034) must always be the last step
  before committing a phase's changes

______________________________________________________________________

## Parallel Opportunities

### Phase 3 (US1) — parallel file creation

```text
After T006 (ks.yaml):
  T007 → ocirepository.yaml   [parallel]
  T008 → externalsecret.yaml  [parallel]
  T009 → httproute.yaml       [parallel]
Then:
  T010 → helmrelease.yaml     [sequential — references ocirepository]
  T011 → kustomization.yaml   [sequential — lists all other files]
  T012 → namespace kustomization update
  T013 → lint + validate
```

### Phase 5 (US3) — parallel across Loki and Alloy

```text
  T017 → loki/ks.yaml         [sequential]
  T018 → loki/ocirepository   [parallel with T019]
  T019 → loki/helmrelease     [parallel with T018, then sequential to finish loki]
  T020 → loki/kustomization   [after T018+T019]

  T021 → alloy/ks.yaml        [parallel with T017+T018+T019]
  T022 → alloy/ocirepository  [parallel]
  T023 → alloy/helmrelease    [parallel with T022]
  T024 → alloy/kustomization  [after T022+T023]

  T025 → kps helmrelease update (Loki data source)
  T026 → namespace kustomization update
  T027 → lint + validate
```

### Phase 7 (Polish) — fully parallel

```text
  T031 → README.md update     [parallel]
  T032 → ARCHITECTURE.md update [parallel]
Then:
  T033 → lint
  T034 → dev:validate
  T035 → open PR
```

______________________________________________________________________

## Implementation Strategy

### MVP First (User Story 1 Only — Phases 1–3)

1. Complete Phase 1: Verify OCI URLs + create 1Password items
2. Complete Phase 2: Confirm cluster prerequisites
3. Complete Phase 3: Deploy kube-prometheus-stack (Prometheus + Grafana + dashboards + PVC)
4. **STOP and validate**: Dashboards load, scrape targets are `up`, PVC is Bound
5. This alone satisfies SC-001, SC-002, SC-004, SC-006 from the spec

### Incremental Delivery

1. **MVP** (Phases 1–3): Metrics + dashboards → validate → merge or keep on branch
2. **+ Alerting** (Phase 4): Add Slack alerts → validate test alert fires → merge
3. **+ Logs** (Phase 5): Add Loki + Alloy → validate log queries + navigation → merge
4. **+ Persistence** (Phase 6): Verify PVC behavior under restarts → document → merge
5. **Polish** (Phase 7): README + ARCHITECTURE + final lint → open PR

______________________________________________________________________

## Notes

- `[P]` tasks = different files, no write conflicts — safe to implement simultaneously
- `[Story]` label maps each task to its spec user story for traceability
- Always run `task lint` before `task dev:validate` — yamlfmt changes must be applied first
- `task lint` will always fail the `no-commit-to-branch` hook on `main` — this is expected
- Commit after each phase's `task dev:validate` passes to keep history clean
- Alloy pipeline config (T023) is the most complex task — refer to
  `specs/004-observability-platform/contracts/loki-label-schema.md` for required label names
- After live cluster testing, always run `task dev:stop` to restore the cluster to `main`
