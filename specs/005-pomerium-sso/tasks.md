# Tasks: Replace Envoy OAuth with Pomerium SSO

**Input**: Design documents from `/specs/005-pomerium-sso/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Organization**: Tasks are grouped by user story so each increment can be implemented and validated cleanly.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: User story label (`[US1]`, `[US2]`, `[US3]`)

______________________________________________________________________

## Phase 1: Setup (Shared SOPS & ArgoCD Prerequisites)

**Purpose**: Prepare SOPS encryption rules and ArgoCD project settings for Pomerium manifests.

- [x] T001 Update SOPS creation rules for `kubernetes/workloads/network/pomerium/ingresses.sops.yaml` (and remove obsolete `envoy-gateway/oauth-policy*` rule after cleanup) in `.sops.yaml`
- [x] T002 [P] Add `pomerium/bootstrap` Secret exception to `orphanedResources.ignore` in `kubernetes/argocd/appproject.yaml`
- [x] T003 [P] Remove `gateway.envoyproxy.io/SecurityPolicy` `ignoreDifferences` from `kubernetes/argocd/applicationset.yaml`

______________________________________________________________________

## Phase 2: Foundational (Pomerium Core Deployment)

**Purpose**: Deploy Pomerium Ingress Controller (`v0.34.1`) with persistent storage, Google OAuth IdP config, and monitoring.

- [x] T004 Create `1Gi` `node-local` PersistentVolumeClaim for Pomerium databroker in `kubernetes/workloads/network/pomerium/pvc.yaml`
- [x] T005 [P] Create `PodMonitor` for `pomerium-metrics` in `kubernetes/workloads/network/pomerium/podmonitor.yaml`
- [x] T006 [P] Create SOPS-encrypted Google IdP Secret placeholder (`client_id`, `client_secret`) in `kubernetes/workloads/network/pomerium/google-idp-secret.sops.yaml`
- [x] T007 Create `Pomerium` global CRD (`global` in `pomerium` namespace, `https://oauth.${SECRET_DOMAIN}`, `network/${SECRET_DOMAIN/./-}-production-tls`, `google-idp`, `bootstrap`, `storage.file.path`) in `kubernetes/workloads/network/pomerium/pomerium.yaml`
- [x] T008 Create `kubernetes/workloads/network/pomerium/kustomization.yaml` referencing `https://github.com/pomerium/ingress-controller/config/default?ref=v0.34.1`, pinning `pomerium-gen-secrets` tag to `v0.34.1` with Renovate tracking, patching `Deployment/pomerium` with `Recreate`, `fsGroup: 65532`, and `/var/lib/pomerium` volume mount, and patching `Service/pomerium-proxy` with `192.168.1.149` and `external-dns` annotations

**Checkpoint**: `kustomize build kubernetes/workloads/network/pomerium` renders cleanly and passes `validate-kubernetes-schema.sh`.

______________________________________________________________________

## Phase 3: User Story 1 - Identity-Aware SSO for Protected Applications (Priority: P1) 🎯 MVP

**Goal**: Route all 7 protected apps (`agentsview`, `paseo`, `herdr`, `hermes-agent`, `openclaw`, `argocd`, `grafana`) through Pomerium via Cloudflare Tunnel and permit Pomerium traffic in workload network policies.

**Independent Test**: Offline render validates all 7 `Ingress` definitions, Cloudflare Tunnel routes point to `pomerium-proxy.pomerium.svc.cluster.local:443`, and `CiliumNetworkPolicy` rules allow `pomerium` proxy pods.

- [x] T009 [US1] Update Cloudflare Tunnel ingress rules for `agentsview`, `paseo`, `herdr`, `hermes`, `openclaw`, `grafana`, `oauth`, and `argocd` to target `https://pomerium-proxy.pomerium.svc.cluster.local:443` (removing `oauth-users`) in `kubernetes/workloads/network/cloudflare-tunnel/values.yaml`
- [x] T010 [P] [US1] Update `CiliumNetworkPolicy` ingress selector to allow `pomerium` proxy pods in `kubernetes/workloads/apps/agentsview/networkpolicy.yaml`
- [x] T011 [P] [US1] Update `CiliumNetworkPolicy` ingress selector to allow `pomerium` proxy pods in `kubernetes/workloads/apps/herdr/networkpolicy.yaml`
- [x] T012 [P] [US1] Update `CiliumNetworkPolicy` ingress selector to allow `pomerium` proxy pods in `kubernetes/workloads/apps/hermes-agent/networkpolicy.yaml`
- [x] T013 [P] [US1] Update `CiliumNetworkPolicy` ingress selector to allow `pomerium` proxy pods in `kubernetes/workloads/apps/openclaw/networkpolicy.yaml`
- [x] T014 [P] [US1] Update `CiliumNetworkPolicy` ingress selector to allow `pomerium` proxy pods in `kubernetes/workloads/apps/paseo/networkpolicy.yaml`
- [x] T015 [P] [US1] Remove `route:` block from `kubernetes/workloads/apps/agentsview/values.yaml` and `HTTPRoute` capability from `kubernetes/workloads/apps/agentsview/kustomization.yaml`
- [x] T016 [P] [US1] Remove `route:` block from `kubernetes/workloads/apps/herdr/values.yaml` and `HTTPRoute` capability from `kubernetes/workloads/apps/herdr/kustomization.yaml`
- [x] T017 [P] [US1] Remove `route:` block from `kubernetes/workloads/apps/hermes-agent/values.yaml` and `HTTPRoute` capability from `kubernetes/workloads/apps/hermes-agent/kustomization.yaml`
- [x] T018 [P] [US1] Remove `route:` block from `kubernetes/workloads/apps/openclaw/values.yaml` and `HTTPRoute` capability from `kubernetes/workloads/apps/openclaw/kustomization.yaml`
- [x] T019 [P] [US1] Remove `route:` block from `kubernetes/workloads/apps/paseo/values.yaml` and `HTTPRoute` capability from `kubernetes/workloads/apps/paseo/kustomization.yaml`
- [x] T020 [P] [US1] Disable `grafana.route.main` in `kubernetes/workloads/observability/kube-prometheus-stack/values.yaml` and remove obsolete `kubernetes/workloads/observability/kube-prometheus-stack/dnsendpoint.yaml` (and its entry in `kubernetes/workloads/observability/kube-prometheus-stack/kustomization.yaml`)
- [x] T021 [P] [US1] Disable `server.httproute.enabled` (retaining `argocd-webhook` on `envoy-external`) in `bootstrap/helmfile.d/templates/values.yaml.gotmpl`

______________________________________________________________________

## Phase 4: User Story 2 - Retain Admins and Users Access Groups (Priority: P2)

**Goal**: Retain `Admins` and `Users` access tiers centrally using YAML anchors inside a single SOPS-encrypted `List` of Pomerium `Ingress` objects, and provide an idempotent operator migration script.

**Independent Test**: Decrypted `ingresses.sops.yaml` structure defines `&admins` and `&users` PPL policy anchors without duplicating email lists across files, and `scripts/migrate-oauth-to-pomerium.sh` passes `shellcheck` and transfers real secrets when run with `age.key`.

- [x] T022 [US2] Create SOPS-encrypted `List` of 7 Pomerium `Ingress` manifests (`agentsview`, `paseo`, `herdr`, `hermes-agent`, `openclaw`, `argocd`, `grafana`) using `&admins` / `&users` YAML anchors and WebSocket annotations in `kubernetes/workloads/network/pomerium/ingresses.sops.yaml` and register it in `kubernetes/workloads/network/pomerium/kustomization.yaml`
- [x] T023 [US2] Create operator migration helper script `scripts/migrate-oauth-to-pomerium.sh` to decrypt `oauth-policy.sops.yaml` and `oauth-client-secret.sops.yaml` (from local worktree or `origin/main`), generate `ingresses.sops.yaml` (using YAML anchors) and `google-idp-secret.sops.yaml`, and encrypt them with SOPS

______________________________________________________________________

## Phase 5: User Story 3 - Decommission Envoy OAuth & Legacy OAuth Plumbing (Priority: P3)

**Goal**: Remove all legacy Envoy OAuth gateways, SecurityPolicies, EnvoyPatchPolicies, `oauth-pages`, and clean up `.sops.yaml`.

**Independent Test**: Zero references to `envoy-oauth-*` or `oauth-pages` remain in `kubernetes/` manifests, and `task dev:validate:ci` passes across all workloads.

- [x] T024 [US3] Remove `oauth-denied-override`, `envoy-oauth-admin`, `envoy-oauth-users`, `envoy-oauth-internal`, `https-redirect` OAuth parentRefs, and `home-ops.io/oauth-gateway` selector logic from `kubernetes/workloads/network/envoy-gateway/envoy.yaml`
- [x] T025 [US3] Remove `envoy-oauth-*` Gateways and `envoy-oauth-*-policy` SecurityPolicies from `kubernetes/workloads/network/envoy-gateway/ignore-extraneous-diffs.yaml`
- [x] T026 [US3] Remove `oauth-header-limits.yaml`, `oauth-client-secret.sops.yaml`, `oauth-policy.sops.yaml`, and `oauth-policy-internal.sops.yaml` from `kubernetes/workloads/network/envoy-gateway/kustomization.yaml` and delete those 4 files
- [x] T027 [P] [US3] Delete obsolete `kubernetes/workloads/apps/oauth-pages/` directory (`kustomization.yaml`, `securitypolicy.yaml`, `values.yaml`)
- [x] T028 [US3] Remove obsolete `envoy-gateway/oauth-policy*` rule from `.sops.yaml`

______________________________________________________________________

## Phase 6: Polish, Templates & Documentation

**Purpose**: Keep cluster templates, README, and operational runbooks synchronized with Pomerium.

- [x] T029 [P] Update `templates/config/bootstrap/helmfile.d/templates/values.yaml.gotmpl.j2`, `templates/config/kubernetes/workloads/network/envoy-gateway/kustomization.yaml.j2`, and delete `templates/config/kubernetes/workloads/network/envoy-gateway/oauth-header-limits.yaml.j2`
- [x] T030 [P] Update `README.md`, `docs/ARCHITECTURE.md`, and `docs/APP-ACCESS.md` for Pomerium SSO
- [x] T031 [P] Update `docs/GOOGLE-OAUTH-SETUP.md`, `docs/OIDC-TROUBLESHOOTING.md`, `docs/SECURITYPOLICY-CHANGE-PLAYBOOK.md`, `docs/GATEWAY-ONBOARDING-CHECKLIST.md`, `docs/POST-MERGE-VERIFICATION.md`, and `docs/PASEO-SETUP.md` (and check other `docs/*-SETUP.md` files for stale `envoy-oauth` references)
- [x] T032 Run `task lint`, `task dev:validate:test`, and `task dev:validate:ci` until all checks pass cleanly

______________________________________________________________________

## Dependencies & Execution Order

- **Setup (Phase 1)** -> blocks Phase 2 & Phase 4 SOPS encryption
- **Foundational (Phase 2)** -> blocks Phase 3 & Phase 4 validation
- **User Story 1 (Phase 3)** & **User Story 2 (Phase 4)** -> can execute in parallel once Phase 2 is complete
- **User Story 3 (Phase 5)** -> runs after Phase 3 & Phase 4 so old Envoy OAuth resources are cleanly replaced
- **Polish (Phase 6)** -> runs after Phase 5, ending with full `task lint` + `task dev:validate:ci` verification

## Implementation Strategy

1. Complete Phase 1 & Phase 2 (`network/pomerium` base + SOPS rules).
2. Implement Phase 3 (Tunnel, NetworkPolicies, remove app HTTPRoutes) and Phase 4 (`ingresses.sops.yaml` with YAML anchors + `scripts/migrate-oauth-to-pomerium.sh`).
3. Implement Phase 5 (delete Envoy OAuth + `oauth-pages` resources).
4. Complete Phase 6 (templates + docs + `task lint` + `task dev:validate:ci`).
