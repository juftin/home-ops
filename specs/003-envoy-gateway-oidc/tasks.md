# Tasks: Envoy Gateway OIDC with Google OAuth

**Input**: Design documents from `/specs/003-envoy-gateway-oidc/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Exact file paths are included in each description

______________________________________________________________________

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create directory structure and scaffolding for all new resources

- [x] T001 Create `kubernetes/apps/default/oauth-pages/` directory with `app/` subdirectory (no files yet — just the directory skeleton for Flux Kustomization and app manifests)
- [x] T002 Verify `kubernetes/apps/network/envoy-gateway/app/` contains `kustomization.yaml`, `envoy.yaml`, and `certificate.yaml` as expected before adding new resources

______________________________________________________________________

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared resources that MUST exist before any user story can be deployed — the OAuth client secret is referenced by every SecurityPolicy, and the static pages app is referenced by every OAuth Gateway's logoutRedirectURL.

**⚠️ CRITICAL**: No user story work can be deployed until this phase is complete

- [x] T003 Create `kubernetes/apps/network/envoy-gateway/app/oauth-client-secret.sops.yaml` — Kubernetes `Secret` named `google-oauth-client-secret` in namespace `network` with `stringData.client-secret: "<CLIENT_SECRET>"` (use the contract template at `specs/003-envoy-gateway-oidc/contracts/oauth-client-secret.sops.yaml`); this file must be SOPS-encrypted with the cluster age key before committing
- [x] T004 Create `kubernetes/apps/default/oauth-pages/app/ocirepository.yaml` — `OCIRepository` pointing at the `app-template` Helm chart (mirror the pattern from `kubernetes/apps/default/echo/app/ocirepository.yaml`)
- [x] T005 [P] Create `kubernetes/apps/default/oauth-pages/app/helmrelease.yaml` — `HelmRelease` using `app-template` chart deploying `nginx:alpine`; include an inline `ConfigMap` named `oauth-pages-html` with two keys: `denied.html` (styled "Access Denied — you are not on the authorized email list" page) and `logged-out.html` (styled "You have been logged out" confirmation page); mount the ConfigMap at `/usr/share/nginx/html/`; set `resources.requests.cpu: 5m` and `resources.requests.memory: 16Mi`; expose service on port `80`
- [x] T006 Create `kubernetes/apps/default/oauth-pages/app/kustomization.yaml` — `Kustomization` listing `ocirepository.yaml`, `helmrelease.yaml`, and `httproute.yaml` as resources (mirror the pattern from `kubernetes/apps/default/echo/app/kustomization.yaml`)
- [x] T007 Create `kubernetes/apps/default/oauth-pages/ks.yaml` — Flux `Kustomization` named `oauth-pages` with `path: ./kubernetes/apps/default/oauth-pages/app`, `targetNamespace: default`, `prune: true`, `wait: false`, and `postBuild.substituteFrom` referencing `cluster-secrets` Secret (mirror the pattern from `kubernetes/apps/default/echo/ks.yaml`)

**Checkpoint**: Foundational resources ready — user story implementation can now begin

______________________________________________________________________

## Phase 3: User Story 1 — Protect an Application with Google OAuth (Priority: P1) 🎯 MVP

**Goal**: Operators can opt an application into Google OAuth protection by changing only the app's `parentRefs` Gateway name — no per-app security policy needed. Unauthenticated requests are redirected to Google login.

**Independent Test**: Attach one application's HTTPRoute to `envoy-oauth-external`, visit it in a browser without a session, and confirm a redirect to `accounts.google.com`. Verify that a whitelisted user completing Google login is redirected back to the app and granted access. Confirm a second app remaining on `envoy-external` is accessible with no auth challenge.

### Implementation for User Story 1

- [x] T008 [US1] Add the `envoy-oauth-external` Gateway resource to `kubernetes/apps/network/envoy-gateway/app/envoy.yaml` — append a new `Gateway` manifest after the existing `envoy-internal` Gateway with: `metadata.name: envoy-oauth-external`, `metadata.namespace: network`, `spec.gatewayClassName: envoy`, `spec.infrastructure.annotations["lbipam.cilium.io/ips"]: "192.168.1.149"` and `spec.infrastructure.annotations["external-dns.alpha.kubernetes.io/hostname"]: "oauth-external.${SECRET_DOMAIN}"`, one HTTP listener on port 80, and one HTTPS listener on port 443 with TLS terminated using `${SECRET_DOMAIN/./-}-production-tls` cert and `allowedRoutes.namespaces.from: All` (use `specs/003-envoy-gateway-oidc/contracts/oauth-gateway.yaml` as the template)
- [x] T009 [US1] Update the `https-redirect` HTTPRoute in `kubernetes/apps/network/envoy-gateway/app/envoy.yaml` — add a third `parentRef` entry `- name: envoy-oauth-external\n  namespace: network\n  sectionName: http` alongside the existing `envoy-external` and `envoy-internal` entries so HTTP→HTTPS redirect applies to the new OAuth Gateway
- [x] T010 [US1] Create `kubernetes/apps/network/envoy-gateway/app/oauth-policy-external.sops.yaml` — `SecurityPolicy` named `envoy-oauth-external-policy` in namespace `network` targeting `envoy-oauth-external` Gateway; OIDC config: `provider.issuer: https://accounts.google.com`, `clientID: "<GOOGLE_CLIENT_ID>"`, `clientSecret.name: google-oauth-client-secret`, `clientSecret.namespace: network`, `redirectURL: "https://oauth-external.${SECRET_DOMAIN}/oauth2/callback"`, `logoutPath: /logout`, `logoutRedirectURL: "https://oauth-external.${SECRET_DOMAIN}/logged-out"`, `cookieDomain: "${SECRET_DOMAIN}"`; authorization: `defaultAction: Deny`, one `Allow` rule named `allow-whitelist` with JWT claims `email_verified=true` and `email` values containing at least one placeholder address (use `specs/003-envoy-gateway-oidc/contracts/oauth-policy.sops.yaml` as the template); this file MUST be SOPS-encrypted before committing
- [x] T011 [US1] Create `kubernetes/apps/default/oauth-pages/app/httproute.yaml` — `HTTPRoute` named `oauth-pages` in namespace `default` with `parentRefs` pointing at `envoy-oauth-external` in namespace `network`; two routing rules: one matching `path.Exact: /denied` and one matching `path.Exact: /logged-out`, both with `backendRefs` pointing to the `oauth-pages` Service on port `80` (use `specs/003-envoy-gateway-oidc/contracts/static-pages-httproute.yaml` as the template)
- [x] T012 [US1] Update `kubernetes/apps/network/envoy-gateway/app/kustomization.yaml` — add `- ./oauth-client-secret.sops.yaml` and `- ./oauth-policy-external.sops.yaml` to the `resources:` list
- [x] T013 [US1] Update `kubernetes/apps/default/kustomization.yaml` — add `- ./oauth-pages/ks.yaml` to the `resources:` list after the existing `./echo/ks.yaml` entry

**Checkpoint**: At this point, User Story 1 is fully functional — an app can be protected by changing one `parentRefs` line, and unauthenticated users are redirected to Google login

______________________________________________________________________

## Phase 4: User Story 2 — Enforce Email Whitelist (Priority: P2)

**Goal**: Only Google accounts with an email address on the Gateway's whitelist are granted access after successful Google login. Authenticated users not on the whitelist see a custom "access denied" page instead of being looped back to Google.

**Independent Test**: Configure a Google account NOT on the whitelist and complete Google login on an OAuth-protected app. Confirm the response is a redirect to `/denied` (not another Google login redirect and not the app). Confirm a whitelisted Google account proceeds normally.

### Implementation for User Story 2

- [x] T014 [US2] Verify `kubernetes/apps/network/envoy-gateway/app/oauth-policy-external.sops.yaml` (created in T010) contains the `authorization.defaultAction: Deny` field and both JWT claim rules — `email_verified` with value `"true"` and `email` with at least one lowercase email address in `values[]`; confirm no mixed-case email entries exist (per FR-013, Envoy does exact string matching and Google always returns lowercase)
- [x] T015 [US2] Add a `BackendTrafficPolicy` resource to `kubernetes/apps/network/envoy-gateway/app/envoy.yaml` — append after the existing `ClientTrafficPolicy`; named `oauth-denied-override` in namespace `network`; `spec.targetSelectors[0].group: gateway.networking.k8s.io`, `spec.targetSelectors[0].kind: Gateway`, `spec.targetSelectors[0].matchLabels` selecting only OAuth Gateways (or use `name: envoy-oauth-external` directly); `spec.responseOverride[0].match.statusCodes[0].type: Value` with `value: 403`; `spec.responseOverride[0].response.redirect.url: "https://oauth-external.${SECRET_DOMAIN}/denied"` — this intercepts 403 authorization failures from the email whitelist check and redirects users to the access-denied page instead of showing a raw 403

**Checkpoint**: User Story 2 is complete — non-whitelisted authenticated users see `/denied` page; empty whitelist denies all users (fail-closed)

______________________________________________________________________

## Phase 5: User Story 3 — Manage Email Whitelists as Encrypted Secrets (Priority: P3)

**Goal**: Email addresses (PII) are never committed in plaintext. The SOPS-encrypted SecurityPolicy manifest is decrypted automatically in-cluster by Flux's kustomize-controller using the cluster's age key.

**Independent Test**: Clone the repo fresh and inspect `oauth-policy-external.sops.yaml` — email addresses must not be visible in plaintext. Decrypt locally with `sops --decrypt`, modify the email list, re-encrypt, commit, push, and confirm Flux reconciles within one cycle (~10 minutes) and the updated list is active.

### Implementation for User Story 3

- [x] T016 [US3] Verify `kubernetes/apps/network/envoy-gateway/app/oauth-policy-external.sops.yaml` is SOPS-encrypted — the file must contain `sops:` metadata at the bottom with `age:` recipients matching the cluster's age public key; run `grep -c 'ENC\[AES256' oauth-policy-external.sops.yaml` to confirm encrypted values are present and no plaintext email addresses appear outside of the `sops:` metadata block
- [x] T017 [US3] Verify `kubernetes/apps/network/envoy-gateway/app/oauth-client-secret.sops.yaml` is SOPS-encrypted — same verification as T016; confirm `client-secret` value is encrypted and no plaintext credential appears

**Checkpoint**: User Story 3 complete — no PII or credentials committed in plaintext; Flux auto-decrypts both files at reconcile time

______________________________________________________________________

## Phase 6: User Story 4 — Multiple OAuth Gateways with Independent Whitelists (Priority: P4)

**Goal**: Operators can run multiple OAuth Gateways each with a different email whitelist. Applications are grouped by access level via Gateway selection. A user on whitelist A cannot access Gateway-B apps, and vice versa.

**Independent Test**: Configure a second OAuth Gateway (`envoy-oauth-internal`) with a different email list. Attach one app to each Gateway. Confirm that a user on whitelist-A can access Gateway-A apps but is denied on Gateway-B apps (and vice versa). Confirm that adding an app to Gateway-B requires only changing `parentRefs` with zero changes to the SecurityPolicy or whitelist.

### Implementation for User Story 4

- [x] T018 [P] [US4] Add second OAuth Gateway `envoy-oauth-internal` to `kubernetes/apps/network/envoy-gateway/app/envoy.yaml` — append a new Gateway manifest following the same pattern as `envoy-oauth-external` (T008) with: `metadata.name: envoy-oauth-internal`, LB IP `192.168.1.150` (or next available from MetalLB pool), DNS hostname `oauth-internal.${SECRET_DOMAIN}`, same TLS cert and listener structure; also add a third `parentRef` `- name: envoy-oauth-internal\n  namespace: network\n  sectionName: http` to the `https-redirect` HTTPRoute
- [x] T019 [P] [US4] Create `kubernetes/apps/network/envoy-gateway/app/oauth-policy-internal.sops.yaml` — second `SecurityPolicy` named `envoy-oauth-internal-policy` in namespace `network` targeting `envoy-oauth-internal` Gateway; same OIDC config structure as the external policy (T010) but with `redirectURL: "https://oauth-internal.${SECRET_DOMAIN}/oauth2/callback"` and `logoutRedirectURL: "https://oauth-internal.${SECRET_DOMAIN}/logged-out"`; different `email.values[]` list from the external policy (these are the "internal" users); SOPS-encrypt before committing
- [x] T020 [US4] Update `kubernetes/apps/default/oauth-pages/app/httproute.yaml` — add a second entry to `parentRefs` for `envoy-oauth-internal` in namespace `network` so that `/denied` and `/logged-out` routes are reachable from Gateway-B apps
- [x] T021 [US4] Update `kubernetes/apps/network/envoy-gateway/app/kustomization.yaml` — add `- ./oauth-policy-internal.sops.yaml` to the `resources:` list alongside the existing external policy entry

**Checkpoint**: User Story 4 complete — two independent OAuth Gateways with separate email whitelists operating side-by-side

______________________________________________________________________

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Validation, formatting, and documentation cleanup

- [x] T022 Run `task lint` from repo root — `yamlfmt` auto-fixes all YAML indentation and multiline strings; run until clean (second run must pass with no changes)
- [x] T023 Run `task dev:validate` from repo root — `flux-local` renders all HelmReleases and Kustomizations offline; fix any render errors before pushing
- [x] T024 [P] Update `README.md` — add `oauth-pages` to the Apps section with a brief description ("Static access-denied and logout confirmation pages for Envoy Gateway OIDC")
- [x] T025 [P] Update `docs/ARCHITECTURE.md` — add `oauth-pages` to the `default` namespace table and add a row for the new OAuth Gateway resources in the `network` namespace table; note the OIDC SecurityPolicy pattern

______________________________________________________________________

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 completion — blocks all user stories
- **User Stories (Phases 3–6)**: All depend on Phase 2 completion
  - US1 (Phase 3) is the critical path — US2, US3, US4 all build on it
  - US2 depends on US1 (email whitelist verification requires the SecurityPolicy from T010)
  - US3 depends on US1 (SOPS verification applies to files created in US1)
  - US4 depends on US1 (second Gateway follows the same pattern)
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Phase 2 — no dependency on other stories — **start here**
- **User Story 2 (P2)**: Requires US1 complete (verifies SecurityPolicy from T010; adds BackendTrafficPolicy to envoy.yaml)
- **User Story 3 (P3)**: Requires US1 complete (verifies SOPS encryption of files created in T010, T003)
- **User Story 4 (P4)**: Requires US1 complete (adds second Gateway to same envoy.yaml, same pattern)

### Within Each User Story

- T008 (Gateway) → T009 (https-redirect update) → T010 (SecurityPolicy) → T011 (HTTPRoute) → T012 (kustomization) → T013 (default kustomization)
- T008 and T004/T005 can run in parallel (different files)
- T018 and T019 can run in parallel (different files — separate Gateway and separate policy)

### Parallel Opportunities

- T004, T005 (oauth-pages ocirepository + helmrelease) can run in parallel
- T008 and T004/T005 can run in parallel (different namespaces / files)
- T018 and T019 (second Gateway + second policy) can run in parallel
- T024 and T025 (README + ARCHITECTURE) can run in parallel
- T016 and T017 (SOPS verifications) can run in parallel

______________________________________________________________________

## Parallel Example: User Story 1

```bash
# Run these foundational tasks in parallel (different files):
Task T004: "Create kubernetes/apps/default/oauth-pages/app/ocirepository.yaml"
Task T005: "Create kubernetes/apps/default/oauth-pages/app/helmrelease.yaml"

# Then run US1 gateway + policy in parallel:
Task T008: "Add envoy-oauth-external Gateway to envoy.yaml"
Task T010: "Create oauth-policy-external.sops.yaml"  # can start as soon as T003 is done
```

## Parallel Example: User Story 4

```bash
# Run these in parallel (completely different files):
Task T018: "Add envoy-oauth-internal Gateway to envoy.yaml"
Task T019: "Create oauth-policy-internal.sops.yaml"
```

______________________________________________________________________

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001–T002)
2. Complete Phase 2: Foundational — T003, T004, T005, T006, T007 (shared resources)
3. Complete Phase 3: User Story 1 — T008–T013 (one OAuth Gateway protecting one app)
4. **STOP and VALIDATE**: Run `task lint && task dev:validate`; use `task dev:start` to test on live cluster
5. Verify unauthenticated visits redirect to Google login
6. Verify whitelisted user can complete login and access the app
7. Verify unprotected apps are unaffected

### Incremental Delivery

1. Setup + Foundational → Shared infrastructure ready
2. User Story 1 → One app protected with Google OAuth (MVP! Can demo/test here)
3. User Story 2 → Email whitelist enforced with custom denied page
4. User Story 3 → SOPS encryption verified (security audit checkpoint)
5. User Story 4 → Multiple Gateways for different access groups
6. Polish → Lint, validate, docs

### Operator Steps (Outside GitOps)

Before deploying US1, the operator must:

1. Create a Google OAuth 2.0 Client ID in Google API Console (Web Application type)
2. Register redirect URI: `https://oauth-external.${SECRET_DOMAIN}/oauth2/callback`
3. Copy the Client ID (goes into `oauth-policy-external.sops.yaml` as plaintext `clientID`) and Client Secret (goes into `oauth-client-secret.sops.yaml` as encrypted `client-secret`)
4. Allocate a new MetalLB IP (`192.168.1.149`) for the OAuth Gateway (verify it's unused: `kubectl get svc -A | grep LoadBalancer`)

______________________________________________________________________

## Notes

- All `.sops.yaml` files MUST be SOPS-encrypted before committing — `task configure` or manual `sops --encrypt` both work
- Email addresses in `oauth-policy-*.sops.yaml` MUST be lowercase — Google returns lowercase emails; Envoy does exact string matching (FR-013)
- `task lint` always fails on `main` (no-commit-to-branch hook) — run it on the feature branch
- After `task dev:start`, always run `task dev:stop` — even if something went wrong
- The `oauth-client-secret.sops.yaml` is shared across all OAuth Gateways — only one Secret is needed cluster-wide
- `BackendTrafficPolicy` responseOverride for 403 handles the case where `defaultAction: Deny` triggers — it redirects the raw 403 to the `/denied` page URL
- See `specs/003-envoy-gateway-oidc/quickstart.md` for the full operator runbook including email list update workflow
