# Quickstart: Headlamp + Flux Plugin

This guide describes the files to create/update to complete the Headlamp deployment. The
`headlamp-app` branch already has the OCIRepository, HelmRelease, and namespace-level
Kustomization. This guide covers the missing pieces.

______________________________________________________________________

## Prerequisites

- The `headlamp-app` branch work is merged or cherry-picked into `002-headlamp-flux`
- External Secrets Operator is running with `ClusterSecretStore/onepassword` in `Ready` state
- The `headlamp-admin-token` item exists in the 1Password **homelab** vault as a Password-type item
- The `envoy-external` Gateway is running in the `network` namespace

______________________________________________________________________

## Files to Create

### 1. `kubernetes/apps/observability/headlamp/app/serviceaccount.yaml`

```yaml
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/core/serviceaccount_v1.json
apiVersion: v1
kind: ServiceAccount
metadata:
  name: headlamp-admin
  namespace: observability
```

### 2. `kubernetes/apps/observability/headlamp/app/clusterrolebinding.yaml`

```yaml
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/rbac.authorization.k8s.io/clusterrolebinding_v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: headlamp-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: headlamp-admin
    namespace: observability
```

### 3. `kubernetes/apps/observability/headlamp/app/externalsecret.yaml`

```yaml
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: headlamp-admin-token
  namespace: observability
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword
  target:
    name: headlamp-admin-token
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: headlamp-admin-token
```

> [!NOTE]
> This uses `dataFrom.extract` to pull all fields from the `headlamp-admin-token`
> 1Password item into a single Kubernetes secret. If only the `password` field is needed,
> replace with `data[0].remoteRef: {key: headlamp-admin-token, property: password}`.

### 4. `kubernetes/apps/observability/headlamp/app/httproute.yaml`

```yaml
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/gateway.networking.k8s.io/httproute_v1.json
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: headlamp
  namespace: observability
spec:
  hostnames: ['headlamp.${SECRET_DOMAIN}']
  parentRefs:
    - name: envoy-external
      namespace: network
      sectionName: https
  rules:
    - backendRefs:
        - name: headlamp
          namespace: observability
          port: 80
      matches:
        - path:
            type: PathPrefix
            value: /
```

______________________________________________________________________

## Files to Update

### 5. `kubernetes/apps/observability/headlamp/app/kustomization.yaml`

Add all new resource files:

```yaml
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./clusterrolebinding.yaml
  - ./externalsecret.yaml
  - ./helmrelease.yaml
  - ./httproute.yaml
  - ./serviceaccount.yaml
```

### 6. `kubernetes/apps/observability/headlamp/ks.yaml`

Add `postBuild.substituteFrom` so `${SECRET_DOMAIN}` is substituted in the HTTPRoute hostname:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app headlamp
  namespace: &namespace observability
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  interval: 1h
  path: ./kubernetes/apps/observability/headlamp/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
  prune: true
  retryInterval: 2m
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: *namespace
  timeout: 5m
  wait: false
```

______________________________________________________________________

## Validate

```bash
task lint           # auto-fix YAML formatting
task dev:validate   # offline render of all HelmReleases and Kustomizations
```

## Accessing Headlamp

1. Navigate to `https://headlamp.${SECRET_DOMAIN}` (e.g., `https://headlamp.juftin.dev`)
2. Retrieve the token from 1Password under **headlamp-admin-token → password field**
3. Paste the token into the Headlamp login screen
4. Navigate to the **Flux** section in the sidebar to view GitOps resource status
