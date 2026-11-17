# App Access

Public and LAN-only apps use chart-native `route` (Gateway API `HTTPRoute`) and `ingress`
(Tailscale) settings in each app's `values.yaml`. [echo](../kubernetes/workloads/apps/echo/values.yaml)
is the public example; [Lunch Money](../kubernetes/workloads/apps/lunchmoney/values.yaml) is the
internal Gateway and Tailscale example; [Paseo](../kubernetes/workloads/apps/paseo/values.yaml)
includes Tailscale private access alongside Pomerium SSO.

## Public or Internal (Envoy Gateway)

For an app with one Service, the chart automatically selects the Service and its
primary port. Add:

```yaml
route:
  app:
    hostnames: ['my-app.${SECRET_DOMAIN}']
    parentRefs:
      - name: envoy-external
        namespace: network
        sectionName: https
```

Choose the Gateway:

| Gateway          | Access                                                  |
| ---------------- | ------------------------------------------------------- |
| `envoy-external` | Public Cloudflare Tunnel; application auth only         |
| `envoy-internal` | Internal LAN Gateway; cluster local DNS via k8s-gateway |

In the app's `kustomization.yaml`, include the API capability in its existing
`helmCharts` entry so offline Helm rendering emits stable HTTPRoutes:

```yaml
apiVersions:
  - gateway.networking.k8s.io/v1/HTTPRoute
```

## Google SSO (Pomerium)

OAuth-protected apps are routed by **Pomerium Ingress Controller** (`ingressClassName: pomerium`)
rather than per-app `values.yaml` `route:` blocks so the `Admins` and `Users` lists stay
encrypted once in [groups.sops.yaml](../kubernetes/workloads/network/pomerium/groups.sops.yaml) and
injected across routes via Kustomize `replacements`:

1. Add a plaintext `Ingress` entry in
   [Pomerium ingresses](../kubernetes/workloads/network/pomerium/ingresses.yaml) labeled
   `pomerium.io/group: admins` or `pomerium.io/group: users` (see
   [Playbook](SECURITYPOLICY-CHANGE-PLAYBOOK.md) to edit group members).
2. Add the app hostname to
   [Cloudflare Tunnel](../kubernetes/workloads/network/cloudflare-tunnel/values.yaml) before the
   `*.${SECRET_DOMAIN}` wildcard pointing to
   `https://pomerium-proxy.pomerium.svc.cluster.local:443` with
   `originServerName: oauth.${SECRET_DOMAIN}`.
3. If the app enforces a `CiliumNetworkPolicy`, allow ingress from `pomerium-proxy` pods in the
   `pomerium` namespace (`app.kubernetes.io/name: pomerium`, `app.kubernetes.io/component: proxy`).

Public apps on `envoy-external` use the existing wildcard without a tunnel edit.

## Tailscale

Add this beside `route` (or standalone) in `values.yaml`, changing the hostname, Service and port:

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

This creates `https://my-app.<tailnet-DNS-suffix>`. Keep both a Pomerium `Ingress` and Tailscale
`ingress` for SSO plus private access; use only `ingress` for Tailscale-only access. Tailscale
bypasses Pomerium SSO, so retain application authentication where needed. See
[Tailscale setup](TAILSCALE-SETUP.md) for operator and hostname prerequisites.

`argocd-webhook` (`webhooks.${SECRET_DOMAIN}/argocd/api/webhook`) remains an `HTTPRoute` on
`envoy-external` in [bootstrap values](../bootstrap/helmfile.d/templates/values.yaml.gotmpl); update
the bootstrap release with `task argocd:bootstrap` when changing it.

For charts without native route settings, keep ordinary HTTPRoute/Ingress manifests
beside the app. When moving existing manifests into chart values, remove their
files and Kustomization resource entries to avoid duplicate resources.

Run `task lint` then `task dev:validate`. Use the normal branch testing workflow
for live checks and always finish with `task dev:stop`.
