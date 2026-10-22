<div align="center">

<img src="https://i.imgur.com/I48mUYX.png" align="center" width="300px"/>

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/2604_fe0f/512.gif" alt="⚙️" width="20" height="20"> home-ops <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f680/512.gif" alt="🚀" width="20" height="20">

_... Homelab managed with ArgoCD, Renovate, and GitHub
Actions_ <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f916/512.gif" alt="🤖" width="16" height="16">

</div>

______________________________________________________________________

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/2699_fe0f/512.gif" alt="⚙️" width="20" height="20"> Infrastructure

- **[Kubernetes](https://kubernetes.io/)**: The container orchestration platform running
  on [Talos](https://talos.dev/).
- **[ArgoCD](https://argo-cd.readthedocs.io/)**: GitOps control plane for Kubernetes.
- **[Renovate](https://renovatebot.com/)**: Automated dependency updates.
- **[GitHub Actions](https://github.com/features/actions)**: CI/CD workflows for automation.
- **[Cloudflare](https://www.cloudflare.com/)**: DNS Services.
- **[Google SSO](https://github.com/envoyproxy/gateway)**: Protect selected endpoints behind Google OAuth2.

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f48e/512.gif" alt="🎡" width="20" height="20"> Components

- **[ArgoCD](https://argo-cd.readthedocs.io/)**: GitOps controller for keeping Kubernetes clusters
  in sync with Git sources. See [GitHub webhook setup](docs/ARGOCD-WEBHOOK-SETUP.md) for immediate
  refreshes on pushes.
- **[cert-manager](https://github.com/cert-manager/cert-manager)**: Creates SSL certificates for
  services in the cluster.
- **[spegel](https://github.com/spegel-org/spegel)**: Stateless cluster local OCI registry mirror.
- **[cloudflared](https://github.com/cloudflare/cloudflared)**: Enables Cloudflare secure access to
  routes.
- **[envoy-gateway](https://github.com/envoyproxy/gateway)**: Kubernetes Gateway API implementation
  for advanced traffic management, security, and routing.
- **[sops](https://github.com/getsops/sops)**: Managed secrets for Kubernetes and Terraform which
  are committed to Git.
- **[external-secrets](https://github.com/external-secrets/external-secrets)**: Integrates external
  secret management systems (particularly
  [1Password](https://external-secrets.io/main/provider/1password-automation/)) with
  Kubernetes Secrets.
- **[cilium](https://github.com/cilium/cilium)**: eBPF-based networking for my workloads.
- **[external-dns](https://github.com/kubernetes-sigs/external-dns)**: Automatically syncs ingress
  DNS records to a DNS provider.
- **[reloader](https://github.com/stakater/Reloader)**: Automatic reloading of Kubernetes resources
  when ConfigMaps or Secrets change.
- **[Agent tools](kubernetes/apps/default/agent-tools/app/install-agents.sh)**: Shared init installer
  for Codex, Claude Code, Antigravity, and the GitHub CLI in Paseo, OpenClaw, and Herdr.
- **[local-path-provisioner](https://github.com/rancher/local-path-provisioner)**: Dynamic
  node-local persistent volume provisioning.
- **[Tailscale](https://tailscale.com/)**: Kubernetes operator for private access to cluster applications.
  See [setup](docs/TAILSCALE-SETUP.md).
- **[Renovate runner](https://github.com/renovatebot/renovate)**: Scheduled dependency updates
  for topic-tagged repositories, with GitHub App authentication and persistent cache.
  Initially suspended pending credential setup and cutover; see [setup](docs/RENOVATE-SETUP.md).

See [App access](docs/APP-ACCESS.md) for app-local OAuth, public Cloudflare,
and Tailscale examples using the existing chart values.

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f3a1/512.gif" alt="🎡" width="20" height="20"> Apps

- **[echo](https://github.com/mendhak/docker-http-https-echo)**: Simple HTTP/HTTPS echo server for
  testing.
- **[Camply](https://github.com/juftin/camply)**: The campsite finder ⛺️, finder of available campsites
  at recreation.gov and beyond, with frontend, API backend, Celery worker/beat, and Postgres database. See [setup](docs/CAMPLY-SETUP.md).
- **[Paseo](https://github.com/getpaseo/paseo)**: Self-hosted coding-agent daemon and web UI behind
  admin Google SSO, with private Tailscale access and persistent workspaces. See [setup](docs/PASEO-SETUP.md).
- **[Herdr](https://github.com/herdrdev/herdr)**: Persistent coding-agent terminals with
  [herdr web ui](https://github.com/devswha/herdr-web-ui) behind admin Google SSO, with token
  authentication, isolated provider tools, and persistent workspaces. See [setup](docs/HERDR-SETUP.md).
- **[OpenClaw](https://github.com/openclaw/openclaw)**: Personal AI assistant gateway and Control UI
  behind admin Google SSO, with persistent state and shared coding tools. See [setup](docs/OPENCLAW-SETUP.md).
- **[Hermes Agent](https://github.com/NousResearch/hermes-agent)**: Self-improving AI agent
  with Gateway API server and Web Dashboard behind admin Google SSO. See [setup](docs/HERMES-SETUP.md).
- **[Lunch Money](https://github.com/juftin/lunchmoney-app)**: MCP server and financial
  dashboard for Lunch Money with web API, PostgreSQL database, Valkey distributed locking, and
  scheduled synchronization, accessible internally and via Tailscale. See [setup](docs/LUNCHMONEY-SETUP.md).
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

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f52e/512.gif" alt="🔮" width="20" height="20"> Hardware

| Device                   | Num | Processor | Cores | OS Disk    | Data Disk | Memory | OS    | Function   |
| ------------------------ | --- | --------- | ----- | ---------- | --------- | ------ | ----- | ---------- |
| HP EliteDesk 800 G6 Mini | 1   | i5-10500T | 6     | 256GB NVMe | 1TB NVMe  | 32GB   | Talos | Kubernetes |

\*\*more nodes to be added soon

______________________________________________________________________

### <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f91d/512.gif" alt="🤝️" width="20" height="20"> Special Thanks

- [onedr0p](https://github.com/onedr0p): for the
  [template](https://github.com/onedr0p/cluster-template) to create this repo
  and the [home-ops](https://github.com/onedr0p/home-ops) project with more apps and components
- [home-operations](https://github.com/home-operations): for their
  [container images](https://github.com/home-operations/containers),
  [helm charts](https://github.com/home-operations/charts-mirror), and
  [discord community](https://discord.gg/home-operations)
