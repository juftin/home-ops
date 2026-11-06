# Runner Configuration Contract

## GitOps inputs

| Setting                    | Initial value                                             | Consumer                                        |
| -------------------------- | --------------------------------------------------------- | ----------------------------------------------- |
| Controller namespace       | `arc-system`                                              | Controller app and runner RoleBindings          |
| Runner namespace           | `arc-runners`                                             | Controller watch flag and scale-set resources   |
| Controller service account | `actions-runner-controller`                               | Both charts; explicit to avoid live Helm lookup |
| Chart source               | `oci://ghcr.io/actions/actions-runner-controller-charts`  | Existing Kustomize Helm renderer                |
| Chart versions             | Controller and runner charts 0.15.0, updated together     | Renovate Kustomize manager                      |
| Runner name                | `home-ops`                                                | `runnerScaleSetName` and workflow `runs-on`     |
| Repository URL             | `https://github.com/juftin/home-ops`                      | `githubConfigUrl`                               |
| Credential reference       | `home-ops-runner-github`                                  | `githubConfigSecret`, string only               |
| Minimum / maximum          | 0 / 2                                                     | Autoscaling runner set                          |
| Container execution        | Explicit pinned-chart DinD template; automatic mode unset | Runner PodSpec                                  |
| Job permissions            | No-permission service account; token automount disabled   | Runner PodSpec                                  |

See [plan.md](../plan.md) for initial resource/volume budgets and quota. Increase concurrency only
alongside a capacity review and matching quota. EmptyDir limits rely on kubelet eviction behavior.

## External secret interface

- Store: existing `ClusterSecretStore/onepassword`.
- Item: `home-ops-runner`; property: `github_token`.
- Target namespace/name: `arc-runners/home-ops-runner-github`.
- Target key: `github_token`, unmodified string.
- Refresh: one hour, following repository conventions.
- Lifecycle: `creationPolicy: Owner`, `deletionPolicy: Retain`; document target Secret cleanup
  during teardown rather than assuming deletion of the remote value removes local credentials.
- Token resource owner: `juftin`; selected repository: `home-ops`; Administration read/write;
  Metadata read implicit. No workflow execution permission is requested for registration.
- Expiration and renewal date must be recorded in the operator's secret manager.

Missing/invalid credentials must surface as ESO status or controller/listener errors. Credentials
must never be printed during verification. Confirm Secret existence/key names without reading values.

## Network interface

No inbound public endpoint. Separate policy selectors distinguish runner, listener, and controller.

| Source                             | Allowed destinations                                          | Purpose                                      |
| ---------------------------------- | ------------------------------------------------------------- | -------------------------------------------- |
| Runner and nested Docker workloads | CoreDNS pods, TCP/UDP 53                                      | DNS through Cilium DNS policy                |
| Runner and nested Docker workloads | Required public FQDNs, TCP 443                                | GitHub, artifacts, public image pulls        |
| Controller/listener                | CoreDNS; GitHub API/actions endpoints TCP 443; Kubernetes API | Reconciliation and queue management          |
| External log collector             | Existing Kubernetes API/log access                            | Collect stdout; no new runner ingress needed |

Initial GitHub FQDN inventory: `github.com`, `api.github.com`, `*.actions.githubusercontent.com`,
`codeload.github.com`, `*.blob.core.windows.net`, `objects.githubusercontent.com`,
`objects-origin.githubusercontent.com`, `github-releases.githubusercontent.com`,
`github-registry-files.githubusercontent.com`, `ghcr.io`, and `pkg-containers.githubusercontent.com`.
These cover runner communication, action downloads, result upload, updates, and image pulls;
OIDC token permissions are not granted merely by allowing the endpoint.

Include Docker Hub authentication/registry and image-layer CDN hosts used by the selected
images. Confirm their redirect targets during smoke pulls; default deny reveals missing
dependencies. Do not open all ports or all destinations to repair a failed image pull.
Sources: [GitHub runner communication reference](https://docs.github.com/en/actions/reference/runners/self-hosted-runners#accessible-domains-by-function)
and [Docker image distribution allowlist](https://docs.docker.com/desktop/enterprise/allow-list/).

Deny unrelated cluster/LAN/private/special destinations and host/API entities for job workloads.
Because Cilium deny wins, carve allowed CoreDNS addresses out of private-range denies. Match DNS
pod labels and namespace from rendered CoreDNS resources. Apply the same restrictions to nested
Docker traffic; verify with build/run and job-container probes. Cilium policies reduce ordinary
network exposure and do not contain a compromised privileged daemon.

## Lifecycle outputs

- Readiness evidence includes ESO Ready, running controller/listener, registered scale set, and
  a successful dispatched job. Accepted manifests alone are insufficient.
- Loki retains runner diagnostics after pod deletion; complete step logs remain in GitHub.
- Teardown drains jobs and removes runner resources before credentials, controller, or namespaces.
