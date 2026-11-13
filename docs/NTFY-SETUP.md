# ntfy Setup

[ntfy](https://ntfy.sh) provides pub-sub notifications with no application authentication:

| Address                                          | Subscribe               | Publish                                 |
| ------------------------------------------------ | ----------------------- | --------------------------------------- |
| `https://ntfy.camply.rocks` through public Envoy | Anyone, no credentials  | Blocked                                 |
| `http://ntfy.ntfy.svc.cluster.local:8080`        | Cluster callers         | Cluster callers, no credentials         |
| `https://ntfy.<tailnet-DNS-suffix>`              | Allowed tailnet clients | Allowed tailnet clients, no credentials |

The public hostname uses an explicit Cloudflare Tunnel rule and the `envoy-external` Gateway's
`ntfy-https` listener, without Google SSO. The shared `camply-rocks-production` certificate covers
`ntfy.camply.rocks`; ExternalDNS discovers its DNS record from the HTTPRoute. In the mobile
app, set this as the default server and subscribe to topics without adding a user. All topics and
cached messages are publicly readable; topic names are not an authorization boundary.

The workload lives in `kubernetes/workloads/apps/ntfy/` and runs in namespace `ntfy`,
matching ArgoCD's `kubernetes/workloads/apps/*` discovery rule. ArgoCD creates the namespace.
If ntfy was previously deployed manually in `default`, its PVC data does not move automatically;
follow the [namespace migration runbook](APP-NAMESPACE-MIGRATION.md) for the `ntfy` claim before
activating this namespace change. Do not remove a populated source PVC without protecting its PV.

## Network boundary

The public HTTPRoute allowlists GET requests for topic pages, subscription endpoints (`json`,
`sse`, `raw`, `ws`, `auth`), web assets, health/config/account reads, and attachment downloads
(GET/HEAD). Everything else has no matching route and returns 404. There is no catch-all backend
rule. Blocking only POST/PUT is insufficient because ntfy supports
[GET publishing](https://docs.ntfy.sh/publish/#webhooks-publish-via-get) at `/topic/publish`,
`/topic/send`, and `/topic/trigger`, plus GET message clear/delete endpoints. These are excluded.
Review the allowlist against `server/server.go` whenever upgrading ntfy.

The ClusterIP Service exposes the full API. The Tailscale operator's private Ingress forwards
straight to that Service, allowing publishing from clients permitted by the existing tailnet ACLs.
No Funnel is enabled. Do not expose this Service through another public route, tunnel, NodePort,
or LoadBalancer: it intentionally has no authentication.

An ingress NetworkPolicy permits port 8080 only from cluster pods, including Envoy and the private
Tailscale proxy, and port 9090 only from the observability namespace. Cluster publishers must also
have egress permission to ntfy; existing isolated agent policies do not automatically grant this.
The public route controls which operations Envoy forwards; the NetworkPolicy controls direct
backend reachability. Forwarded client IP headers do not grant publishing access.

There is no ntfy ExternalSecret, user database configuration, password, or access token. Any old
`user.db` on the PVC is unused. Public web publishing, browser push registration, and UnifiedPush
publishing are excluded by the read allowlist; native mobile subscriptions and WebSockets remain
available.

## Configuration

Settings live in [values.yaml](../kubernetes/workloads/apps/ntfy/values.yaml):

| Setting                                            | Value                       | Purpose                                                   |
| -------------------------------------------------- | --------------------------- | --------------------------------------------------------- |
| `auth-default-access`                              | `read-write`                | No application authentication; networking controls writes |
| `enable-login` / `require-login` / `enable-signup` | `false`                     | No account login or registration                          |
| `behind-proxy`                                     | `true`                      | Rate limiting uses forwarded client IPs                   |
| `proxy-trusted-hosts`                              | `10.42.0.0/16`              | Trust pod-network proxy hops                              |
| `cache-duration`                                   | `24h`                       | Retain messages for reconnecting subscribers              |
| `attachment-*`                                     | 2G total, 15M per file, 24h | Persistent attachment limits                              |
| `upstream-base-url`                                | `https://ntfy.sh`           | Forward message IDs for iOS instant notifications         |
| `metrics-listen-http`                              | `:9090`                     | Dedicated metrics port scraped by ServiceMonitor          |

One non-root replica runs `ntfy serve` on port 8080 with a read-only root filesystem and dropped
capabilities. A 5Gi `node-local` PVC at `/var/lib/ntfy` stores `cache.db` and attachments. The
`Recreate` strategy prevents concurrent SQLite writers. Health probes use `GET /v1/health`.
The shared Envoy BackendTrafficPolicy disables request timeouts for streaming subscriptions.

## Usage

```bash
# Subscribe from anywhere, without credentials
curl -N https://ntfy.camply.rocks/homelab/json

# Publish from a cluster workload, without credentials
curl -d "Backup finished" http://ntfy.ntfy.svc.cluster.local:8080/homelab

# Publish from a permitted tailnet device, without credentials
curl -d "Backup finished" https://ntfy.<tailnet-DNS-suffix>/homelab
```

## Verification

Run the route regression checks with `python3.15 scripts/tests/test-ntfy-public-route.py`.
After branch deployment, check the HTTPRoute's `Accepted` and `ResolvedRefs` conditions, verify the
Tailscale Ingress has an address, and exercise the actual network paths:

```bash
# Public publishing must have no route (expect 404)
curl -s -o /dev/null -w '%{http_code}\n' -d test https://ntfy.camply.rocks/test
curl -s -o /dev/null -w '%{http_code}\n' -X PUT -d test https://ntfy.camply.rocks/test
curl -s -o /dev/null -w '%{http_code}\n' -H 'Content-Type: application/json' \
  -d '{"topic":"test","message":"test"}' https://ntfy.camply.rocks/
for alias in publish send trigger; do
  curl -s -o /dev/null -w '%{http_code}\n' "https://ntfy.camply.rocks/test/$alias?message=test"
done

# From a cluster publisher pod: expect 200 without credentials
curl -s -o /dev/null -w '%{http_code}\n' -d test http://ntfy.ntfy.svc.cluster.local:8080/test

# From a permitted tailnet device: expect 200 without credentials
curl -s -o /dev/null -w '%{http_code}\n' -d test https://ntfy.<tailnet-DNS-suffix>/test

# Public subscription retrieves the published message (expect 200)
curl -s -w '\n%{http_code}\n' 'https://ntfy.camply.rocks/test/json?poll=1&since=all'
curl -s https://ntfy.camply.rocks/v1/health
```

Also verify SSE, WebSocket subscriptions, web assets, and attachment downloads work publicly;
GET clear/delete endpoints remain blocked; and direct access from outside the cluster/tailnet
cannot reach the backend. Finish live branch testing with `task dev:stop`.
