<div align="center">

<img src="https://i.imgur.com/I48mUYX.png" align="center" width="300px"/>

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/2604_fe0f/512.gif" alt="⚙️" width="20" height="20"> home-ops <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f680/512.gif" alt="🚀" width="20" height="20">

_... Homelab managed with Flux, Renovate, and GitHub
Actions_ <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f916/512.gif" alt="🤖" width="16" height="16">

</div>

______________________________________________________________________

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/2699_fe0f/512.gif" alt="⚙️" width="20" height="20"> Infrastructure

- **[Kubernetes](https://kubernetes.io/)**: The container orchestration platform running
  on [Talos](https://talos.dev/).
- **[Flux](https://fluxcd.io/)**: GitOps tool for Kubernetes.
- **[Renovate](https://renovatebot.com/)**: Automated dependency updates.
- **[GitHub Actions](https://github.com/features/actions)**: CI/CD workflows for automation.
- **[Cloudflare](https://www.cloudflare.com/)**: DNS Services.

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f48e/512.gif" alt="🎡" width="20" height="20"> Components

- **[Flux](https://fluxcd.io/)**: GitOps tool for keeping Kubernetes clusters in
  sync with Git sources.
- **[cert-manager](https://github.com/cert-manager/cert-manager)**: Creates SSL certificates for
  services in the cluster.
- **[spegel](https://github.com/spegel-org/spegel)**: Stateless cluster local OCI registry mirror.
- **[cloudflared](https://github.com/cloudflare/cloudflared)**: Enables Cloudflare secure access to
  routes.
- **[envoy-gateway](https://github.com/envoyproxy/gateway)**: Kubernetes Gateway API implementation
  for advanced traffic management, security, and routing.
- **[sops](https://github.com/getsops/sops)**: Managed secrets for Kubernetes and Terraform which
  are commited to Git.
- **[external-secrets](https://github.com/external-secrets/external-secrets)**: Integrates external
  secret management systems (
  particularly [1Password](https://external-secrets.io/main/provider/1password-automation/)) with
  Kubernetes Secrets.
- **[cilium](https://github.com/cilium/cilium)**: eBPF-based networking for my workloads.
- **[external-dns](https://github.com/kubernetes-sigs/external-dns)**: Automatically syncs ingress
  DNS records to a DNS provider.
- **[reloader](https://github.com/stakater/Reloader)**: Automatic reloading of Kubernetes resources
  when ConfigMaps or Secrets change.
- **[local-path-provisioner](https://github.com/rancher/local-path-provisioner)**: Dynamic
  node-local persistent volume provisioning.

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f3a1/512.gif" alt="🎡" width="20" height="20"> Apps

- **[echo](https://github.com/mendhak/docker-http-https-echo)**: Simple HTTP/HTTPS echo server for
  testing.
- **[headlamp](https://headlamp.dev/)**: Kubernetes dashboard with the
  [Flux plugin](https://github.com/headlamp-k8s/headlamp-plugin-flux) for GitOps visibility.
- **[Grafana](https://grafana.com/)**: Cluster dashboards and Explore UI.
- **[Prometheus](https://prometheus.io/)**: Scrapes and stores Kubernetes metrics with 30-day
  retention.
- **[Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/)**: Routes firing and
  resolved alerts to Slack.
- **[Loki](https://grafana.com/oss/loki/)**: Aggregates and stores Kubernetes logs for 7 days.
- **[Alloy](https://grafana.com/oss/alloy-opentelemetry-collector/)**: DaemonSet log shipper that
  labels pod logs and forwards them to Loki.
- **[oauth-pages](https://nginx.org/)**: Static access-denied and logout confirmation pages for
  Envoy Gateway OIDC, including route rewrites from friendly paths to static HTML files.

### OIDC Behavior

- Protected routes redirect unauthenticated requests directly to the configured OIDC provider.
- Selected operational UIs can be attached to OAuth-protected gateways, while other routes can stay on the external gateway.
- Authorization denials are presented with a custom `/denied` page.
- Logout flow lands on a custom `/logged-out` confirmation page.
- See [`docs/OIDC-TROUBLESHOOTING.md`](./docs/OIDC-TROUBLESHOOTING.md) for operational checks and
  recovery steps.

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f52e/512.gif" alt="🔮" width="20" height="20"> Hardware

| Device                   | Num | Processor | Cores | OS Disk    | Data Disk | Memory | OS    | Function   |
| ------------------------ | --- | --------- | ----- | ---------- | --------- | ------ | ----- | ---------- |
| HP EliteDesk 800 G6 Mini | 1   | i5-10500T | 6     | 256GB NVMe | 1TB NVMe  | 32GB   | Talos | Kubernetes |

\*\* more nodes to be added soon

______________________________________________________________________

### <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f91d/512.gif" alt="🤝️" width="20" height="20"> Special Thanks

- [onedr0p](https://github.com/onedr0p): for the
  [template](https://github.com/onedr0p/cluster-template) to create this repo
  and the [home-ops](https://github.com/onedr0p/home-ops) project with more apps and components
- [home-operations](https://github.com/home-operations): for their
  [container images](https://github.com/home-operations/containers),
  [helm charts](https://github.com/home-operations/charts-mirror), and
  [discord community](https://discord.gg/home-operations)
