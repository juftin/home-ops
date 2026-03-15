# home-ops Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-02-21

## Active Technologies
- YAML manifests, Bash scripts, Taskfile tasks (GitOps/IaC repository) + Kubernetes, ArgoCD, Helmfile, Kustomize, SOPS + age, External Secrets Operator, Task (001-replace-flux-argocd)
- Kubernetes API resources in-cluster; encrypted Git-tracked secrets (`*.sops.yaml`) (001-replace-flux-argocd)

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
- 001-replace-flux-argocd: Added YAML manifests, Bash scripts, Taskfile tasks (GitOps/IaC repository) + Kubernetes, ArgoCD, Helmfile, Kustomize, SOPS + age, External Secrets Operator, Task

- 004-observability-platform: Added YAML manifests; Helm chart values (no compiled code)
- 003-envoy-gateway-oidc: Added YAML/Kubernetes manifests; Envoy Gateway v1.7+; Flux v2; SOPS + age + `gateway.envoyproxy.io/v1alpha1` SecurityPolicy (OIDC + JWT authorization

<!-- MANUAL ADDITIONS START -->

<!-- MANUAL ADDITIONS END -->
