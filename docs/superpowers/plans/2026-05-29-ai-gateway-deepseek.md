# Envoy AI Gateway + DeepSeek Proxy — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Envoy AI Gateway controller and configure it to proxy OpenAI-format and Anthropic-format requests to DeepSeek at `ai.<domain>`.

**Architecture:** The AI Gateway controller (Helm chart) extends the existing Envoy Gateway, creating a new GatewayClass + Gateway with its own Envoy proxy pods. Two AIServiceBackends (OpenAI + Anthropic schema) wrap two Backends pointing at DeepSeek's API endpoints (`api.deepseek.com` and `api.deepseek.com/anthropic`). A single catch-all AIGatewayRoute sends all model requests to both backends — the AI Gateway filter detects the incoming API format and routes to the matching schema. The DeepSeek API key comes from 1Password via ExternalSecret. Cloudflare Tunnel routes `ai.${SECRET_DOMAIN}` to the new Gateway.

**Tech Stack:** Envoy AI Gateway v0.6.0 (Helm), Envoy Gateway v1.8.0 (existing), bjw-s app-template (existing pattern), External Secrets Operator (existing), Cloudflare Tunnel (existing)

______________________________________________________________________

### Task 1: Create the AI Gateway app directory and kustomization

**Files:**

- Create: `kubernetes/apps/network/ai-gateway/app/kustomization.yaml`

- Create: `kubernetes/apps/network/ai-gateway/app/values.yaml`

- [ ] **Step 1: Create the kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./gateway.yaml
  - ./ai-routes.yaml
  - ./backend-security.yaml
  - ./externalsecret.yaml
helmCharts:
  - name: ai-gateway-crds-helm
    repo: oci://docker.io/envoyproxy
    version: v0.6.0
    releaseName: aieg-crd
    namespace: network
    includeCRDs: true
  - name: ai-gateway-helm
    repo: oci://docker.io/envoyproxy
    version: v0.6.0
    releaseName: aieg
    namespace: network
    includeCRDs: true
    valuesFile: ./values.yaml
```

- [ ] **Step 2: Create the values.yaml**

```yaml
config:
  aiGateway:
    envoyGateway:
      namespace: network
```

- [ ] **Step 3: Commit**

```bash
git add kubernetes/apps/network/ai-gateway/app/kustomization.yaml \
        kubernetes/apps/network/ai-gateway/app/values.yaml
git commit -m "✨ Add AI Gateway controller kustomization"
```

______________________________________________________________________

### Task 2: Create Gateway, GatewayClass, and EnvoyProxy

**Files:**

- Create: `kubernetes/apps/network/ai-gateway/app/gateway.yaml`

- [ ] **Step 1: Create gateway.yaml with GatewayClass, EnvoyProxy, Gateway, and ClientTrafficPolicy**

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy-ai-gateway
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
---
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: ai-gateway-proxy
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyDeployment:
        replicas: 2
        container:
          imageRepository: mirror.gcr.io/envoyproxy/envoy
          resources:
            requests:
              cpu: 100m
            limits:
              memory: 1Gi
      envoyService:
        externalTrafficPolicy: Cluster
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: envoy-ai-gateway
  labels:
    home-ops.io/cloudflare-dns: "true"
  annotations:
    external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
spec:
  gatewayClassName: envoy-ai-gateway
  infrastructure:
    annotations:
      external-dns.alpha.kubernetes.io/hostname: ai.${SECRET_DOMAIN}
      lbipam.cilium.io/ips: "192.168.1.152"
    parametersRef:
      group: aigateway.envoyproxy.io
      kind: EnvoyProxy
      name: ai-gateway-proxy
  listeners:
    - name: http
      protocol: HTTP
      port: 80
    - name: https
      protocol: HTTPS
      port: 443
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - group: ""
            kind: Secret
            name: ${SECRET_DOMAIN/./-}-production-tls
---
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: ClientTrafficPolicy
metadata:
  name: ai-gateway-buffer-limit
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: envoy-ai-gateway
  connection:
    bufferLimit: 50Mi
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/apps/network/ai-gateway/app/gateway.yaml
git commit -m "✨ Add AI Gateway GatewayClass, EnvoyProxy, and Gateway"
```

______________________________________________________________________

### Task 3: Create Backends, AIServiceBackends, and AIGatewayRoute

**Files:**

- Create: `kubernetes/apps/network/ai-gateway/app/ai-routes.yaml`

- [ ] **Step 1: Create ai-routes.yaml**

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: Backend
metadata:
  name: deepseek
spec:
  endpoints:
    - fqdn:
        hostname: api.deepseek.com
        port: 443
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: Backend
metadata:
  name: deepseek-anthropic
spec:
  endpoints:
    - fqdn:
        hostname: api.deepseek.com
        port: 443
---
apiVersion: aigateway.envoyproxy.io/v1beta1
kind: AIServiceBackend
metadata:
  name: deepseek-openai
spec:
  schema:
    name: OpenAI
  backendRef:
    name: deepseek
    kind: Backend
    group: gateway.envoyproxy.io
---
apiVersion: aigateway.envoyproxy.io/v1beta1
kind: AIServiceBackend
metadata:
  name: deepseek-anthropic
spec:
  schema:
    name: Anthropic
  backendRef:
    name: deepseek-anthropic
    kind: Backend
    group: gateway.envoyproxy.io
---
apiVersion: aigateway.envoyproxy.io/v1beta1
kind: AIGatewayRoute
metadata:
  name: deepseek
spec:
  parentRefs:
    - name: envoy-ai-gateway
      kind: Gateway
      group: gateway.networking.k8s.io
  rules:
    - backendRefs:
        - name: deepseek-openai
        - name: deepseek-anthropic
```

> **Note:** `Backend/deepseek-anthropic` points to the same `api.deepseek.com:443` as `Backend/deepseek`. The `/anthropic` path prefix is handled by the AI Gateway's Anthropic schema — when the AIServiceBackend uses `schema: Anthropic`, the AI Gateway constructs requests to `/anthropic/v1/messages`. If this assumption is wrong and the Backend needs an explicit path prefix, we'll use an EnvoyPatchPolicy to add a URL rewrite. Verify after deployment.

- [ ] **Step 2: Commit**

```bash
git add kubernetes/apps/network/ai-gateway/app/ai-routes.yaml
git commit -m "✨ Add DeepSeek Backends, AIServiceBackends, and AIGatewayRoute"
```

______________________________________________________________________

### Task 4: Create BackendSecurityPolicies

**Files:**

- Create: `kubernetes/apps/network/ai-gateway/app/backend-security.yaml`

- [ ] **Step 1: Create backend-security.yaml**

```yaml
apiVersion: aigateway.envoyproxy.io/v1beta1
kind: BackendSecurityPolicy
metadata:
  name: deepseek-openai
spec:
  targetRefs:
    - group: aigateway.envoyproxy.io
      kind: AIServiceBackend
      name: deepseek-openai
  type: APIKey
  apiKey:
    secretRef:
      name: deepseek-api-key
---
apiVersion: aigateway.envoyproxy.io/v1beta1
kind: BackendSecurityPolicy
metadata:
  name: deepseek-anthropic
spec:
  targetRefs:
    - group: aigateway.envoyproxy.io
      kind: AIServiceBackend
      name: deepseek-anthropic
  type: APIKey
  apiKey:
    secretRef:
      name: deepseek-api-key
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/apps/network/ai-gateway/app/backend-security.yaml
git commit -m "🔐 Add DeepSeek BackendSecurityPolicies"
```

______________________________________________________________________

### Task 5: Create ExternalSecret for the DeepSeek API key

**Files:**

- Create: `kubernetes/apps/network/ai-gateway/app/externalsecret.yaml`

- [ ] **Step 1: Create externalsecret.yaml**

```yaml
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: deepseek
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword
  target:
    name: deepseek-api-key
    creationPolicy: Owner
    deletionPolicy: Retain
  dataFrom:
    - extract:
        key: deepseek
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/apps/network/ai-gateway/app/externalsecret.yaml
git commit -m "🔐 Add DeepSeek API key ExternalSecret"
```

______________________________________________________________________

### Task 6: Update Cloudflare Tunnel for ai.<domain>

**Files:**

- Modify: `kubernetes/apps/network/cloudflare-tunnel/app/values.yaml`

- [ ] **Step 1: Add the ai hostname ingress before the wildcard route**

In `kubernetes/apps/network/cloudflare-tunnel/app/values.yaml`, under `configMaps.config.data.config.yaml`, add this entry before the `*.${SECRET_DOMAIN}` wildcard:

```yaml
  - hostname: ai.${SECRET_DOMAIN}
    originRequest:
      http2Origin: true
      originServerName: ai.${SECRET_DOMAIN}
    service: https://envoy-ai-gateway.{{ .Release.Namespace 
      }}.svc.cluster.local:443
```

The insertion point is after the `argocd` entry and before the `*.${SECRET_DOMAIN}` wildcard entry. The resulting order should be:

```
grafana -> oauth -> oauth-users -> argocd -> ai -> * (wildcard) -> 404
```

- [ ] **Step 2: Verify the edit with task lint**

```bash
task lint
```

Expected: Passes (may need two runs for yamlfmt to normalize).

- [ ] **Step 3: Commit**

```bash
git add kubernetes/apps/network/cloudflare-tunnel/app/values.yaml
git commit -m "🚇 Route ai subdomain to AI Gateway"
```

______________________________________________________________________

### Task 7: Validate offline

**Files:**

- None (validation only)

- [ ] **Step 1: Run lint**

```bash
task lint
```

Expected: All hooks pass on second run (yamlfmt may reformat on first run).

- [ ] **Step 2: Run dev:validate**

```bash
task dev:validate
```

Expected: All ArgoCD app manifests render successfully. If the AI Gateway Helm charts fail to render (e.g., missing values key), adjust `values.yaml` accordingly.

If `dev:validate` fails with Helm-related errors for the new charts, check:

- Chart version exists: `helm show chart oci://docker.io/envoyproxy/ai-gateway-helm --version v0.6.0`
- Values schema: `helm show values oci://docker.io/envoyproxy/ai-gateway-helm --version v0.6.0`

Fix any issues, re-run lint + validate, then:

- [ ] **Step 3: Commit any fixes**

```bash
git add -A && git commit -m "🐛 Fix validation issues from lint/dev:validate"
```

______________________________________________________________________

### Task 8: Update README and ARCHITECTURE docs

**Files:**

- Modify: `README.md`

- Modify: `docs/ARCHITECTURE.md`

- [ ] **Step 1: Add AI Gateway to README apps section**

In `README.md`, under the `## Apps` section, add:

```markdown
- **[Envoy AI Gateway](https://github.com/envoyproxy/ai-gateway)**: AI traffic gateway proxying
  DeepSeek (and future providers) with unified API routing.
```

- [ ] **Step 2: Add AI Gateway to ARCHITECTURE**

In `docs/ARCHITECTURE.md`, add `envoy-ai-gateway` to the relevant layer description. Under the control plane or gateway section, add:

```markdown
- **Envoy AI Gateway** extends Envoy Gateway with AI-specific routing, schema translation, and
  provider API key management. It runs its own Gateway and proxy pods alongside the existing
  Gateways.
```

- [ ] **Step 3: Commit**

```bash
git add README.md docs/ARCHITECTURE.md
git commit -m "📝 Document Envoy AI Gateway"
```

______________________________________________________________________

### Task 9: Branch testing (requires cluster access)

**Files:**

- None (live testing only)

> This task requires cluster access (`kubeconfig`). Skip if unavailable.

- [ ] **Step 1: Push branch and start branch testing**

```bash
task dev:start
```

Expected: Branch pushed, ArgoCD root + ApplicationSet patched to track branch refs.

- [ ] **Step 2: Wait for AI Gateway controller reconcile**

```bash
kubectl wait --timeout=5m -n network deployment/ai-gateway-controller --for=condition=Available
```

Expected: `deployment/ai-gateway-controller condition met`

- [ ] **Step 3: Verify Gateway is programmed**

```bash
kubectl get gateway -n network envoy-ai-gateway
```

Expected: `Programmed: True`

- [ ] **Step 4: Verify ExternalSecret syncs**

```bash
kubectl get externalsecret -n network deepseek
kubectl get secret -n network deepseek-api-key
```

Expected: ExternalSecret shows `Ready: True`. The Secret `deepseek-api-key` exists and has an `apiKey` field.

If the 1Password item hasn't been created yet, this step will fail. Create it:

```bash
op item create \
  --category "API Credential" \
  --vault homelab \
  --title deepseek \
  "apiKey[password]=<YOUR_DEEPSEEK_API_KEY>"
```

- [ ] **Step 5: Test an API call**

```bash
curl -s https://ai.${SECRET_DOMAIN}/v1/chat/completions \
  -H "Authorization: Bearer test" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-chat","messages":[{"role":"user","content":"hello"}]}' | head -c 200
```

Expected: A response from DeepSeek (may be an auth error if using a test key, but should NOT be a 404 or connection error).

- [ ] **Step 6: Verify Gateway pods are running**

```bash
kubectl get pods -n network -l gateway.envoyproxy.io/gateway-name=envoy-ai-gateway
```

Expected: 2 pods Running (matching replicas: 2).

- [ ] **Step 7: Stop branch testing**

```bash
task dev:stop
```

Expected: ArgoCD refs restored to `main`.

- [ ] **Step 8: Commit any fixes from testing**

```bash
git add -A && git commit -m "🐛 Fix issues found during branch testing"
```
