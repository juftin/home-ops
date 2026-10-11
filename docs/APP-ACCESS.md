# App Access

Use the app-template chart's existing `route` and `ingress` settings in the app's
`values.yaml`. [Paseo](../kubernetes/apps/default/paseo/app/values.yaml) includes
admin OAuth and Tailscale; [echo](../kubernetes/apps/default/echo/app/values.yaml)
is the public example.

## Public or OAuth

For an app with one Service, the chart automatically selects the Service and its
primary port. Add:

```yaml
route:
  app:
    hostnames: ['my-app.${SECRET_DOMAIN}']
    parentRefs:
      - name: envoy-oauth-admin
        namespace: network
        sectionName: https
```

Choose the Gateway:

| Gateway             | Access                                                    |
| ------------------- | --------------------------------------------------------- |
| `envoy-external`    | Public Cloudflare Tunnel; application authentication only |
| `envoy-oauth-admin` | Google SSO, admins                                        |
| `envoy-oauth-users` | Google SSO, users                                         |

In the app's `kustomization.yaml`, include the API capability in its existing
`helmCharts` entry so offline Helm rendering emits stable HTTPRoutes:

```yaml
apiVersions:
  - gateway.networking.k8s.io/v1/HTTPRoute
```

**OAuth has one additional shared edit:** add the app hostname to
[Cloudflare Tunnel](../kubernetes/apps/network/cloudflare-tunnel/app/values.yaml)
before the public wildcard. Copy an entry for the same group; admins use
`envoy-oauth-admin` with TLS origin `oauth.${SECRET_DOMAIN}`, users use
`envoy-oauth-users` with TLS origin `oauth-users.${SECRET_DOMAIN}`. Public apps use
the existing wildcard without a tunnel edit. OAuth utility pages already cover
all app hosts through their wildcard; callback protection remains section-scoped.

For multiple ports or paths, specify `route.app.rules`; see
[Hermes Agent](../kubernetes/apps/default/hermes-agent/app/values.yaml).

## Tailscale

Add this beside `route` in `values.yaml`, changing the hostname, Service and port:

```yaml
ingress:
  tailscale:
    suffix: tailscale
    className: tailscale
    defaultBackend:
      service:
        name: my-app
        port:
          number: 8080
    tls:
      - hosts: [my-app]
```

This creates `https://my-app.<tailnet-DNS-suffix>`. Keep both blocks for OAuth plus
private access; use only `ingress` for Tailscale-only access. Tailscale bypasses
Google SSO, so retain application authentication where needed. See
[Tailscale setup](TAILSCALE-SETUP.md) for operator and hostname prerequisites.

Grafana uses its own chart's `grafana.route.main` settings in
[kube-prometheus-stack values](../kubernetes/apps/observability/kube-prometheus-stack/app/values.yaml).
ArgoCD uses `server.httproute` in its
[bootstrap values](../bootstrap/helmfile.d/templates/values.yaml.gotmpl); update its
Helm release with `task argocd:bootstrap` to deploy changes. The chart names its
HTTPRoute `argocd-server` and uses the existing HTTP Service port when
`server.insecure` is enabled.
Shared OAuth utility routes also live in
[oauth-pages values](../kubernetes/apps/default/oauth-pages/app/values.yaml), including
their named callback, logout, denied, and logged-out rules.

For charts without native route settings, keep ordinary HTTPRoute/Ingress manifests
beside the app. When moving existing manifests into chart values, remove their
files and Kustomization resource entries to avoid duplicate resources.

Run `task lint` then `task dev:validate`. Use the normal branch testing workflow
for live checks and always finish with `task dev:stop`.
