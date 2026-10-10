# Tailscale Setup

Tailscale provides a private HTTPS endpoint for Paseo at `https://paseo.<tailnet-DNS-suffix>`.
Install Tailscale on each client device and join the same tailnet. Browser, native, and CLI
connections use the existing daemon password without an Envoy OAuth redirect. The public
Paseo hostname continues to use admin Google SSO.

The Kubernetes operator runs in `tailscale` and creates a userspace proxy for the Paseo Ingress.
It manages HTTPS certificates and WebSocket proxying. Funnel and Kubernetes API access are
disabled. See the official [operator installation](https://tailscale.com/docs/kubernetes-operator/install-operator)
and [Ingress documentation](https://tailscale.com/docs/kubernetes-operator/ingress).

## Tailnet Configuration

Enable MagicDNS and HTTPS certificates in the Tailscale admin console's DNS settings. Record
the DNS suffix displayed there, such as `tail123abc.ts.net`, without a scheme, hostname, or
trailing dot.

Merge these entries into the existing tailnet policy. The grant permits tailnet administrators
to connect to Paseo on HTTPS; use the intended user or group instead if other devices need access.
Existing broader grants or ACLs still apply.

```json
{
  "tagOwners": {
    "tag:k8s-operator": [
      "autogroup:admin"
    ],
    "tag:k8s": [
      "tag:k8s-operator"
    ],
    "tag:paseo": [
      "tag:k8s-operator"
    ]
  },
  "grants": [
    {
      "src": [
        "autogroup:admin"
      ],
      "dst": [
        "tag:paseo"
      ],
      "ip": [
        "tcp:443"
      ]
    }
  ]
}
```

Create an OAuth client under **Trust credentials** with the `tag:k8s-operator` tag and write
permissions for **General / Services**, **Devices / Core**, and **Keys / Auth Keys**. Store its
credentials in 1Password rather than Helm values or Git.

## 1Password

Create an **API Credential** item named `tailscale` in the **homelab** vault with these fields:

| Field                  | Value                         | Kubernetes destination                                       |
| ---------------------- | ----------------------------- | ------------------------------------------------------------ |
| `client_id`            | Tailscale OAuth client ID     | `tailscale/operator-oauth:client_id`                         |
| `client_secret`        | Tailscale OAuth client secret | `tailscale/operator-oauth:client_secret`                     |
| `TAILSCALE_DNS_SUFFIX` | Tailnet DNS suffix            | `<consumer-namespace>/tailscale-config:TAILSCALE_DNS_SUFFIX` |

Keep `PASEO_PASSWORD` in the existing `paseo` item. The Tailscale app owns the operator credentials
and a `ClusterExternalSecret` that distributes only `TAILSCALE_DNS_SUFFIX` to consumer namespaces
as `tailscale-config`. It currently selects `default`; add namespace names to its selector to
share the configuration with other apps. OAuth credentials remain in the `tailscale` namespace.
See [ClusterExternalSecret](https://external-secrets.io/latest/api/clusterexternalsecret/).

Paseo imports `tailscale-config` through `envFrom`; Kubernetes expands the DNS suffix in
`PASEO_HOSTNAMES` before starting the daemon. Paseo's own ExternalSecret manages only its daemon
password. The tailnet hostname is never stored in Git. Reloader restarts workloads when their
referenced Secrets change.

Populate these fields before syncing the applications. Sync `home-ops-root` to register the
`tailscale` namespace and application, then sync `tailscale` before `paseo`. ArgoCD creates the
`tailscale` namespace automatically.
The operator waits for `operator-oauth` to exist before starting. A missing 1Password field
causes External Secrets reconciliation to fail; check its status if the endpoint does not appear.

## Connect and Verify

```bash
kubectl get externalsecret -n tailscale tailscale
kubectl get clusterexternalsecret tailscale-config
kubectl get externalsecret -n default tailscale-config
kubectl get externalsecret -n default paseo
kubectl rollout status deployment/operator -n tailscale
kubectl get ingress -n default paseo-tailscale
```

The Ingress `ADDRESS` should show `paseo.<tailnet-DNS-suffix>`. Confirm the proxy device appears
in the Tailscale admin console tagged `tag:paseo`. From an authorized device with Tailscale on,
open `https://<Ingress-ADDRESS>` and enter the Paseo daemon password.

For Paseo's **Add host → Direct connection**, use the Ingress address as the host, port **443**,
**SSL enabled**, and the same daemon password. Use this address instead of `localhost`.
Verify a provider session streams over WebSocket and the public hostname still requires Google
login. Devices without tailnet access should not reach the private endpoint.

For branch testing, run `task lint`, `task dev:validate`, and `task dev:start`; always finish with
`task dev:stop` after live checks.
