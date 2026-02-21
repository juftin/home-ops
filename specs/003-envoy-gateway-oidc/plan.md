# Implementation Plan: Envoy Gateway OIDC with Google OAuth

**Branch**: `003-envoy-gateway-oidc` | **Date**: 2026-02-21 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/003-envoy-gateway-oidc/spec.md`

## Summary

Add Google OAuth protection to selected cluster applications via Envoy Gateway's native OIDC
SecurityPolicy. Multiple OAuth-enabled Gateways are provisioned — each with its own encrypted
email allowlist embedded in a SOPS-encrypted SecurityPolicy manifest — alongside the existing
public Gateways. Operators opt applications in by pointing their HTTPRoute's `parentRefs` at the
appropriate OAuth Gateway. Two static pages (access-denied and logged-out) are deployed as cluster
resources to provide clear feedback to users.

## Technical Context

**Language/Version**: YAML/Kubernetes manifests; Envoy Gateway v1.7+; Flux v2; SOPS + age
**Primary Dependencies**: `gateway.envoyproxy.io/v1alpha1` SecurityPolicy (OIDC + JWT authorization
claims), `cert-manager` (TLS), SOPS + age (secret encryption), Flux kustomize-controller (GitOps),
Google OAuth 2.0 / OIDC (`https://accounts.google.com`)
**Storage**: SOPS-encrypted Kubernetes manifests in Git (SecurityPolicy with embedded email claims;
Kubernetes Secret with OAuth client credentials)
**Testing**: `task lint` (yamlfmt + pre-commit), `task dev:validate` (flux-local render), CI via
GitHub Actions (`flux-local test` + `flux-local diff`)
**Target Platform**: Kubernetes (Talos Linux, bare metal homelab); `network` namespace for Gateway
resources; `default` namespace for static pages app
**Performance Goals**: Authentication redirect latency acceptable for interactive browser use
(~1–2 s); zero overhead for apps on public Gateways
**Constraints**: No plaintext secrets or PII (email addresses) in Git; all sensitive manifests
SOPS-encrypted; GitOps-only changes; fail-closed on missing/malformed whitelist
**Scale/Scope**: 2–5 OAuth Gateways; up to ~100 email entries per whitelist; up to ~50 protected
apps total; single Google OAuth application (one client ID/secret) shared across all OAuth Gateways

## Constitution Check

| Principle                         | Status  | Notes                                                        |
| --------------------------------- | ------- | ------------------------------------------------------------ |
| I. GitOps & Declarative           | ✅ Pass | All resources committed; Flux reconciles; no `kubectl apply` |
| II. IaC & Reproducibility         | ✅ Pass | All gateways, policies, and pages as YAML manifests          |
| III. Template & Bootstrappability | ✅ Pass | Follows existing app structure; uses `${SECRET_DOMAIN}`      |
| IV. Modular Architecture          | ✅ Pass | Apps opt-in via `parentRefs`; no changes to other apps       |
| V. Code Quality                   | ✅ Pass | Follows existing naming conventions; `yamlfmt` enforced      |
| VI. DRY Principles                | ✅ Pass | Email list per-Gateway (not per-app); shared client secret   |
| VII. Observability                | ✅ Pass | Envoy Gateway access logs capture all auth events            |
| VIII. Security & Least Privilege  | ✅ Pass | SOPS-encrypted email list + client secret; no plaintext PII  |
| IX. Testing & Validation          | ✅ Pass | `task lint` + `task dev:validate` before merge               |

No violations. No Complexity Tracking section required.

## Key Technical Decision: Email Allowlist Enforcement

Envoy Gateway's `SecurityPolicy` supports **native JWT claim-based authorization** via the
`authorization.rules[*].principal.jwt.claims` field. When OIDC is configured, Google's ID token
(a JWT with an `email` claim) is automatically available to authorization rules.

The email allowlist is embedded **directly in the SecurityPolicy manifest** as a list of string
values under `authorization.rules[*].principal.jwt.claims[name=email].values[]`. The entire
SecurityPolicy manifest is **SOPS-encrypted in Git**. This eliminates any need for an external
authorization service (ext_authz) and keeps infrastructure minimal.

Email addresses MUST be stored in lowercase in the manifest (Google returns emails in lowercase;
case normalization is enforced by convention and documented in the quickstart).

## Key Technical Decision: Custom Error Pages

Envoy Gateway's `BackendTrafficPolicy` supports `responseOverride` to intercept specific HTTP
status codes and return custom responses. A `403` override will redirect users to a static
access-denied page served by a dedicated nginx deployment in the cluster. The logout page is
served by the same nginx deployment and referenced via `logoutRedirectURL` in the OIDC config.

## Project Structure

### Documentation (this feature)

```text
specs/003-envoy-gateway-oidc/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
kubernetes/apps/network/envoy-gateway/
└── app/
    ├── kustomization.yaml           # add references to new oauth resources
    ├── envoy.yaml                   # add new OAuth Gateway definitions
    ├── certificate.yaml             # (existing — shared TLS cert)
    ├── helmrelease.yaml             # (existing)
    ├── ocirepository.yaml           # (existing)
    ├── podmonitor.yaml              # (existing)
    ├── oauth-client-secret.sops.yaml  # SOPS: Google OAuth client_id + client_secret
    └── oauth-policy-<name>.sops.yaml  # SOPS: SecurityPolicy per OAuth Gateway
                                       # (one file per Gateway, e.g., oauth-policy-external.sops.yaml)

kubernetes/apps/default/
├── kustomization.yaml               # add oauth-pages entry
└── oauth-pages/
    ├── ks.yaml                      # Flux Kustomization
    └── app/
        ├── kustomization.yaml
        ├── ocirepository.yaml       # OCI source for nginx chart
        ├── helmrelease.yaml         # nginx HelmRelease serving static HTML
        └── httproute.yaml           # route /denied and /logged-out on each OAuth Gateway
```

**Structure Decision**: Gateway resources and SecurityPolicies live in the `network` namespace
alongside existing envoy-gateway resources. Static pages live in `default` following the existing
app pattern (HelmRelease + OCIRepository + HTTPRoute). SOPS-encrypted files (`.sops.yaml`) are
automatically decrypted by Flux's kustomize-controller via the cluster's age key.

## Implementation Phases

### Phase 0 — Research ✅ (Complete)

See [`research.md`](./research.md).

### Phase 1 — Design

See [`data-model.md`](./data-model.md), [`contracts/`](./contracts/), [`quickstart.md`](./quickstart.md).

### Phase 2 — Tasks

See [`tasks.md`](./tasks.md) — generated by `/speckit.tasks`.
