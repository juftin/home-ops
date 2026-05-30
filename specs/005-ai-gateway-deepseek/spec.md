# Feature Specification: Envoy AI Gateway + DeepSeek Proxy

**Feature Branch**: `005-ai-gateway-deepseek`
**Created**: 2026-05-29
**Status**: Draft
**Input**: User description: "Implement Envoy AI Gateway and proxy DeepSeek"

## User Scenarios & Testing

### User Story 1 - DeepSeek API Access via Gateway (Priority: P1)

As a homelab operator, I want to send OpenAI-compatible API requests to `ai.<domain>` and have them
proxied through the Envoy AI Gateway to DeepSeek's API, using the AI Gateway's native schema
translation.

**Why this priority**: This is the core MVP. Without working proxy routing, nothing else has value.

**Independent Test**: Send a chat completion request to `https://ai.<domain>/v1/chat/completions`
with a valid API key and verify the response comes back from DeepSeek.

**Acceptance Scenarios**:

1. **Given** the AI Gateway is deployed and the DeepSeek API key is configured, **When** a client
   sends an OpenAI-format chat completion request to `ai.<domain>`, **Then** the request is proxied
   to DeepSeek and the response is returned to the client.
2. **Given** the AI Gateway is deployed, **When** a request includes any model name supported by
   DeepSeek, **Then** the request is routed to the DeepSeek backend without requiring per-model
   route rules.
3. **Given** the AI Gateway is deployed, **When** the DeepSeek API key is rotated in 1Password,
   **Then** the gateway picks up the new key within the ExternalSecret refresh interval.

______________________________________________________________________

### User Story 2 - Multi-Provider Foundation (Priority: P2)

As a homelab operator, I want the AI Gateway deployed with a structure that allows adding additional
providers (OpenAI, Anthropic) later by adding new Backend + AIServiceBackend + BackendSecurityPolicy
resources without architectural changes.

**Why this priority**: The initial deployment establishes the pattern. Adding providers later should
be purely additive.

**Independent Test**: After initial deployment, verify that adding a second AIServiceBackend (e.g.,
OpenAI) with its own BackendSecurityPolicy works without modifying the Gateway or controller config.

**Acceptance Scenarios**:

1. **Given** the AI Gateway is deployed with DeepSeek as the sole backend, **When** an operator adds
   an OpenAI backend with a model-specific route rule, **Then** both providers coexist and route
   correctly based on the `x-ai-eg-model` header.
2. **Given** multiple backends are configured, **When** a request matches a model-specific rule,
   **Then** it routes to the correct provider, and unmatched models fall through to the catch-all
   DeepSeek backend.

______________________________________________________________________

### Edge Cases

- What happens when the DeepSeek API is unreachable? The gateway returns a 502 or 503, surfaced
  through the existing Envoy Gateway metrics.
- What happens when the 1Password ExternalSecret fails to sync? The existing secret remains in
  place (deletionPolicy: Retain), so the gateway continues to function with the last-known API key.
- What happens when the AI Gateway controller pod restarts? The data plane (Envoy proxy) continues
  serving requests; the control plane recovers and re-reconciles CRDs.
- What happens when an unsupported model name is requested? If DeepSeek doesn't support the model,
  DeepSeek returns its own error — the gateway proxies it transparently.

## Requirements

### Functional Requirements

- **FR-001**: Envoy AI Gateway controller MUST be installed via Helm (CRDs + controller) in the
  `envoy-ai-gateway-system` namespace.
- **FR-002**: A dedicated Gateway with class `envoy-ai-gateway` MUST be provisioned with an HTTPS
  listener using the existing `${SECRET_DOMAIN/./-}-production-tls` certificate.
- **FR-003**: A Backend resource MUST be configured pointing to `api.deepseek.com:443`.
- **FR-004**: An AIServiceBackend with OpenAI schema MUST be configured referencing the DeepSeek
  Backend.
- **FR-005**: A BackendSecurityPolicy of type APIKey MUST be configured to inject the DeepSeek API
  key into upstream requests.
- **FR-006**: The DeepSeek API key MUST be sourced from 1Password via ExternalSecret (not
  committed as SOPS).
- **FR-007**: An AIGatewayRoute MUST be configured with a catch-all rule routing all models to the
  DeepSeek backend.
- **FR-008**: Cloudflare Tunnel MUST be updated to route `ai.${SECRET_DOMAIN}` to the AI Gateway's
  service with `originServerName: ai.${SECRET_DOMAIN}`.
- **FR-009**: The AI Gateway Gateway MUST have the `home-ops.io/cloudflare-dns: "true"` label for
  automatic Cloudflare DNS record creation.
- **FR-010**: A 1Password item named `deepseek` MUST exist in the homelab vault with an `apiKey`
  field containing the DeepSeek API key.

### Key Entities

- **GatewayClass/envoy-ai-gateway**: Separate GatewayClass for the AI Gateway data plane, keeping AI
  proxy pods isolated from the existing OAuth Gateway pods.
- **Backend/deepseek**: References `api.deepseek.com:443` — the upstream provider endpoint.
- **AIServiceBackend/deepseek**: Wraps the Backend with the OpenAI schema, telling the AI Gateway
  how to transform requests/responses.
- **BackendSecurityPolicy/deepseek-api-key**: Injects the API key from a Kubernetes Secret into
  requests to the DeepSeek backend.
- **AIGatewayRoute/deepseek**: Catch-all route attaching the DeepSeek backend to the AI Gateway.
- **ExternalSecret/deepseek**: Pulls the `apiKey` field from the `deepseek` 1Password item.
- **Gateway/envoy-ai-gateway**: The data plane Gateway with HTTPS listener, LB IP `192.168.1.152`.

## Success Criteria

- **SC-001**: A chat completion request sent to `https://ai.<domain>/v1/chat/completions` returns a
  valid DeepSeek response.
- **SC-002**: Requests including the DeepSeek API key in the Authorization header are proxied
  successfully, with the AI Gateway injecting its own API key upstream.
- **SC-003**: The AI Gateway Gateway shows `Programmed: True` and `Accepted: True` in `kubectl get gateway -n network envoy-ai-gateway`.
- **SC-004**: `kubectl get externalsecret -n network deepseek` shows `Ready: True` and a
  `deepseek-api-key` Secret is created.
- **SC-005**: `task lint && task dev:validate` both pass.

## Clarifications

### Session 2026-05-29

- Q: Public or internal access? → A: Both — public `ai.<domain>` via Cloudflare Tunnel, plus
  internal cluster access via the Gateway's ClusterIP service.
- Q: OAuth or API key auth? → A: API key-based access control at the gateway level (no OAuth).
- Q: How to manage the DeepSeek API key? → A: ExternalSecret from 1Password; user will populate
  the 1Password item via `op` CLI.
- Q: Which DeepSeek models to route? → A: All models, catch-all route to the DeepSeek backend.
- Q: Rate limiting or token budgets? → A: None for the initial deployment.

## Assumptions

- Envoy AI Gateway v0.5.0+ uses the same `gateway.envoyproxy.io/gatewayclass-controller` as the
  existing Envoy Gateway — the AI Gateway controller extends it rather than replacing it.
- DeepSeek's API is OpenAI-compatible, so the `OpenAI` schema in AIServiceBackend works without
  modification.
- The existing cert-manager certificate (`${SECRET_DOMAIN/./-}-production-tls`) covers
  `ai.<domain>` (wildcard or SAN).
- The AI Gateway will receive LB IP `192.168.1.152` from the Cilium IPAM pool.
- The user will create the `deepseek` 1Password item with the `apiKey` field before or immediately
  after deployment.
