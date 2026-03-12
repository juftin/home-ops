# home-ops Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-02-21

## Active Technologies
- YAML (Kubernetes manifests), Bash task workflow, Markdown specs + Flux, External Secrets Operator + 1Password Connect, Envoy Gateway OIDC (001-fix-headlamp-token-sync)
- Kubernetes Secret resources sourced from 1Password via ExternalSecre (001-fix-headlamp-token-sync)

- YAML manifests; Helm chart values (no compiled code) (004-observability-platform)
- YAML/Kubernetes manifests; Envoy Gateway v1.7+; Flux v2; SOPS + age + `gateway.envoyproxy.io/v1alpha1` SecurityPolicy (OIDC + JWT authorization (003-envoy-gateway-oidc)

## Project Structure

```text
src/
tests/
```

## Commands

# Add commands for YAML manifests; Helm chart values (no compiled code)
# Add commands for YAML/Kubernetes manifests; Envoy Gateway v1.7+; Flux v2; SOPS + age

## Code Style

YAML manifests; Helm chart values (no compiled code): Follow standard conventions
YAML/Kubernetes manifests; Envoy Gateway v1.7+; Flux v2; SOPS + age: Follow standard conventions

## Recent Changes
- 001-fix-headlamp-token-sync: Added YAML (Kubernetes manifests), Bash task workflow, Markdown specs + Flux, External Secrets Operator + 1Password Connect, Envoy Gateway OIDC

- 004-observability-platform: Added YAML manifests; Helm chart values (no compiled code)
- 003-envoy-gateway-oidc: Added YAML/Kubernetes manifests; Envoy Gateway v1.7+; Flux v2; SOPS + age + `gateway.envoyproxy.io/v1alpha1` SecurityPolicy (OIDC + JWT authorization

<!-- MANUAL ADDITIONS START -->

<!-- MANUAL ADDITIONS END -->
