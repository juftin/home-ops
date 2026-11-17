# Research: Replace Envoy OAuth with Pomerium SSO

## 1. Deployment Method: Pomerium Ingress Controller (`v0.34.1`)

**Decision**: Deploy `pomerium/ingress-controller` using Kustomize remote base `https://github.com/pomerium/ingress-controller/config/default?ref=v0.34.1` under `kubernetes/workloads/network/pomerium/`, keeping upstream's `pomerium` namespace (`Namespace/pomerium`).

**Rationale**:

- The legacy `pomerium/pomerium-helm` chart is archived and unmaintained; the official Kubernetes quickstart (`https://www.pomerium.com/docs/deploy/k8s/quickstart`) standardizes on `pomerium/ingress-controller`.
- `config/default?ref=v0.34.1` bundles the Pomerium CRDs (`pomerium.ingress.pomerium.io`, `policyfilters.gateway.pomerium.io`), `IngressClass/pomerium`, `Deployment/pomerium`, `Service/pomerium-proxy`, `Service/pomerium-metrics`, RBAC, and `Job/pomerium-gen-secrets`.
- Pinning the `pomerium-gen-secrets` container image from `:main` to `:v0.34.1` via Kustomize `images:` with a `# renovate:` annotation satisfies Constitution Principle VI (no unpinned mutable `:main` tags).
- `AppProject/home-ops` (`kubernetes/argocd/appproject.yaml`) allows `destinations: namespace: '*'`, so an ArgoCD Application under `kubernetes/workloads/network/pomerium/` cleanly manages `pomerium`-namespace resources and cross-namespace `Ingress` objects.

**Alternatives considered**:

- *Archived `pomerium/pomerium-helm` chart*: Rejected — unmaintained since 2023.
- *Experimental Gateway API (`config/gateway-api`)*: Rejected — Pomerium marks Gateway API as experimental, and Gateway API `ExtensionRef` (`PolicyFilter`) is namespace-scoped, forcing duplication across 7 namespaces.

## 2. Retaining Admins & Users Groups with YAML Anchors and SOPS

**Decision**: Consolidate all 7 Pomerium-protected `Ingress` manifests into a single SOPS-encrypted Kubernetes `List` file (`kubernetes/workloads/network/pomerium/ingresses.sops.yaml`), using YAML anchors (`&admins`, `&users`) on `ingress.pomerium.io/policy` annotations, encrypted via a `.sops.yaml` rule matching `^(ingress\.pomerium\.io/policy)$`.

**Rationale**:

- Kustomize unpacks `apiVersion: v1` / `kind: List` cleanly into individual `Ingress` resources across target namespaces (`agentsview`, `paseo`, `herdr`, `hermes-agent`, `openclaw`, `argocd`, `observability`).
- Each `Ingress` targets its app's native Kubernetes `Service` directly in its own namespace without requiring `ExternalName` Service indirection.
- Encrypting only `ingress.pomerium.io/policy` keeps routing metadata (`host`, `backend`, `allow_websockets: "true"`) readable in Git while ensuring zero email addresses appear in plaintext (Constitution VIII).
- YAML anchors (`&admins`, `&users`) keep the `Admins` and `Users` policy definitions DRY in the decrypted source YAML. Note that `sops --encrypt` resolves anchors into independent encrypted ciphertexts per item; `scripts/migrate-oauth-to-pomerium.sh` and `docs/SECURITYPOLICY-CHANGE-PLAYBOOK.md` support re-generating or updating policies cleanly.

**Alternatives considered**:

- *Per-app `Ingress` in each app's `values.yaml`*: Rejected — YAML anchors cannot span separate files, and `values.yaml` is unencrypted, which would expose emails in plaintext.
- *Single `Ingress` per group with `ExternalName` Services*: Viable, but requires maintaining 7 synthetic `ExternalName` Services and forces identical WebSocket/annotation flags across all apps in a group.

## 3. Global TLS, Authenticate URL, and Databroker Storage

**Decision**:

- Set `spec.authenticate.url: https://oauth.${SECRET_DOMAIN}` on `Pomerium/global`.
- Set `spec.certificates: ["network/${SECRET_DOMAIN/./-}-production-tls"]` on `Pomerium/global` to reuse the existing cert-manager wildcard certificate (`*.${SECRET_DOMAIN}`).
- Configure `spec.storage.file.path: /var/lib/pomerium` backed by a `1Gi` `node-local` PVC (`pomerium-data`) and `strategy: Recreate` + `fsGroup: 65532` on `Deployment/pomerium`.
- Assign `Service/pomerium-proxy` LoadBalancer IP `192.168.1.149` (freed from `envoy-oauth-admin`) with `external-dns.alpha.kubernetes.io/hostname: oauth.${SECRET_DOMAIN}` and `external-dns.kubernetes.io/target: external.${SECRET_DOMAIN}`.

**Rationale**:

- Reusing `https://oauth.${SECRET_DOMAIN}` preserves the existing Google Cloud Console Authorized Redirect URI (`https://oauth.<domain>/oauth2/callback`).
- Global wildcard `certificates` on `Pomerium/global` avoids duplicating TLS Secrets across 7 app namespaces.
- Persistent `file` storage on `node-local` preserves sessions across pod restarts on this single-node Talos cluster without introducing a separate PostgreSQL dependency.

## 4. Network Isolation, Tunneling, and Legacy Cleanup

**Decision**:

- Update `kubernetes/workloads/network/cloudflare-tunnel/values.yaml` so `agentsview`, `paseo`, `herdr`, `hermes`, `openclaw`, `grafana`, `argocd`, and `oauth` forward HTTPS traffic to `https://pomerium-proxy.pomerium.svc.cluster.local:443` with `originServerName: oauth.${SECRET_DOMAIN}` before the `*.${SECRET_DOMAIN}` wildcard. Remove `oauth-users.${SECRET_DOMAIN}`.
- Update `CiliumNetworkPolicy` in `agentsview`, `herdr`, `hermes-agent`, `openclaw`, and `paseo` to permit ingress from `k8s:io.kubernetes.pod.namespace: pomerium`, `app.kubernetes.io/name: pomerium`, `app.kubernetes.io/component: proxy`.
- Remove `envoy-oauth-admin`, `envoy-oauth-users`, `envoy-oauth-internal`, `oauth-denied-override`, `oauth-header-limits.yaml`, `oauth-policy*.sops.yaml`, `oauth-client-secret.sops.yaml`, `apps/oauth-pages/`, `kube-prometheus-stack/dnsendpoint.yaml`, and `SecurityPolicy` `ignoreDifferences` in `applicationset.yaml`.
- Keep `envoy-external` (`echo`, `camply`, `ntfy`, `argocd-webhook`) and `envoy-internal` (`lunchmoney`) untouched.
- Add `Secret/bootstrap` in `pomerium` to `AppProject/home-ops` `orphanedResources.ignore` because `pomerium-gen-secrets` creates it dynamically at runtime.
