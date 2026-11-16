# Contract: Protected Application Ingress & Network Boundaries

## Cloudflare Tunnel (`kubernetes/workloads/network/cloudflare-tunnel/values.yaml`)

All Pomerium-protected hostnames (`agentsview`, `paseo`, `herdr`, `hermes`, `openclaw`, `grafana`, `argocd`, `oauth`) MUST appear before the `*.${SECRET_DOMAIN}` wildcard rule and target:

- `service`: `https://pomerium-proxy.pomerium.svc.cluster.local:443`
- `originRequest.http2Origin`: `true`
- `originRequest.originServerName`: `oauth.${SECRET_DOMAIN}`

## Cilium NetworkPolicy Ingress Contract

Protected workloads with ingress isolation (`agentsview`, `herdr`, `hermes-agent`, `openclaw`, `paseo`) MUST permit TCP traffic on their exposed service ports from:

```yaml
  - fromEndpoints:
      - matchLabels:
          k8s:io.kubernetes.pod.namespace: pomerium
          app.kubernetes.io/name: pomerium
          app.kubernetes.io/component: proxy
```

## Public & Internal Gateway Isolation Contract

- `envoy-external` continues serving `echo`, `camply`, `ntfy`, and `argocd-webhook` (`webhooks.${SECRET_DOMAIN}/argocd/api/webhook`).
- `envoy-internal` continues serving `lunchmoney`.
- No Envoy `SecurityPolicy` or `envoy-oauth-*` Gateways remain in the cluster.
