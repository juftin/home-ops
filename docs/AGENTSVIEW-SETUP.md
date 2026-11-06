# AgentsView Setup

[AgentsView](https://github.com/kenn-io/agentsview) aggregates coding-agent session
history, search, token usage, and costs at `https://agentsview.${SECRET_DOMAIN}`.
Admin Google SSO protects the dashboard; AgentsView also requires its bearer token.
The dashboard reads a shared PostgreSQL database. Each source independently parses
its own files into SQLite and pushes updates to PostgreSQL. The dashboard is not
an HTTP ingestion endpoint. This uses the upstream
[PostgreSQL sync](https://github.com/kenn-io/agentsview/blob/v0.46.1/docs/pg-sync.md)
workflow with AgentsView 0.46.1.

## Credentials and first deployment

Create a **Login** item named `agentsview` in the 1Password **homelab** vault, with
URL `https://agentsview.${SECRET_DOMAIN}` and these fields:

| Field                   | Purpose                                                    |
| ----------------------- | ---------------------------------------------------------- |
| `POSTGRES_PASSWORD`     | Long random database password shared by trusted collectors |
| `AGENTSVIEW_AUTH_TOKEN` | Separate random bearer token for browser/API access        |

ExternalSecrets distribute the database password into `agentsview`, `paseo`,
`herdr`, `openclaw`, and `hermes-agent`. Only the dashboard receives the bearer
token. Create the item before syncing the apps: missing credentials prevent pods
from starting. No secret values belong in Git.

The database Service is exposed privately by the existing Tailscale operator as
`agentsview-db.<tailnet-DNS-suffix>:5432`. Enable MagicDNS and authorize the desired
source devices in your tailnet policy; see [Tailscale setup](TAILSCALE-SETUP.md).
There is no public database route or LAN NodePort. LAN devices join Tailscale just
like your laptop; devices without it can use an SSH tunnel through a trusted
machine with cluster access.

Sync `agentsview` before restarting the agent apps. The dashboard may restart
until PostgreSQL is ready. The application creates its schema automatically.
The database uses a dedicated 10Gi node-local PVC; the dashboard has a 1Gi state
PVC. These volumes do not have an automatic backup configured. Back up PostgreSQL
before upgrades; local collector archives are not a substitute for database backups.
The PostgreSQL password initializes a fresh volume only: changing the 1Password
field later also requires changing the database role password before restarting
consumers.

## Cluster collectors

Paseo, Herdr, OpenClaw, and Hermes each run an `agentsview` sidecar executing
`agentsview pg push --watch --interval 5m`. Each keeps a separate 2Gi node-local
archive PVC and a stable machine display label. Session changes are debounced
for 30 seconds; the five-minute sweep catches missed filesystem notifications.
The source home/data volume is mounted at `/sources` read-only.
An init container seeds `/data/config.toml` once from the app's ConfigMap; it stays
writable so AgentsView can retain generated settings. To change cluster project
filters after enrollment, edit the persisted config and restart the pod, or remove
only `/data/config.toml` to reseed it from updated chart values. Preserve the rest
of `/data`, especially the installation ID and archive. The collector
has no Kubernetes API token, and no service exposes its local archive.

| Source        | Session roots under `/sources`                    |
| ------------- | ------------------------------------------------- |
| Paseo / Herdr | `.claude/projects`, `.codex/sessions`, `.gemini`  |
| OpenClaw      | Above roots plus `.openclaw`                      |
| Hermes        | `.hermes/sessions` and sibling `.hermes/state.db` |

AgentsView can only ingest providers with supported on-disk formats; agent
terminal output alone is not a session source. Missing provider roots yield no
sessions until that provider has run. The Hermes root follows its default home
under `/opt/data`; if that app changes `HERMES_HOME`, update the collector path.
Do not clone collector archives between machines: their persistent installation
IDs distinguish sources even when display names change.

The existing agent isolation policies permit TCP 5432 only to the AgentsView
database endpoints. Database ingress accepts these four apps, the dashboard, and
the operator's proxy for this specific Service. Plain PostgreSQL transport is
limited to cluster networking and the encrypted Tailscale tunnel. Collectors
share the database owner credential and must be trusted: this is a personal
archive, not a multi-tenant service with isolated publishers. Network policies
apply to the whole agent pod, including its main container.

## Enroll a computer or network device

Install the matching CLI from the upstream release (macOS, Linux, or Windows),
join Tailscale, and create `~/.agentsview/config.toml` with restrictive permissions:

```toml
local_machine_name = "my-laptop"

[pg]
url = "postgres://agentsview@agentsview-db.<tailnet-DNS-suffix>:5432/agentsview?sslmode=disable"
allow_insecure = true
# Optional: publish only selected projects.
# projects = ["home-ops"]
```

Replace the tailnet suffix and machine name for each device. Store the database
password in your user's PostgreSQL password file (`~/.pgpass` on Unix; see
[PostgreSQL passfiles](https://www.postgresql.org/docs/current/libpq-pgpass.html)
for Windows). Its entry is:

```text
agentsview-db.<tailnet-DNS-suffix>:5432:agentsview:agentsview:<POSTGRES_PASSWORD>
```

Use `chmod 600 ~/.pgpass ~/.agentsview/config.toml` on Unix. Escape `:` and `\`
in the passfile password with `\`. The password file is read by the PostgreSQL
driver; keep it out of repositories and shell history. `sslmode=disable` is
intentional only for this encrypted tailnet connection.

Start with a one-shot push, then enable continuous collection:

```bash
agentsview pg push
agentsview pg status
agentsview pg push --watch --interval 5m
```

On macOS/Linux, `agentsview pg service install` installs the upstream per-user
background watcher. On Windows, keep the watcher running through your service
manager. Each device needs its own installation and source files; nothing scans
all devices on the LAN automatically. Use the upstream session discovery config
for nonstandard provider directories. Project filters belong in each collector's
`[pg]` section and restrict which projects it publishes.

The archive includes prompts, responses, and tool content, which may contain
credentials. Review project filters before the first push. To collect usage only,
review upstream archive-content settings before ingesting; changing filters does
not guarantee that previously published content is removed.

## Verify and troubleshoot

```bash
kubectl get externalsecret -n agentsview
kubectl get pods,pvc,svc,httproute -n agentsview
kubectl logs -n agentsview deployment/agentsview-app -c app
kubectl logs -n paseo deployment/paseo -c agentsview
kubectl exec -n paseo deployment/paseo -c agentsview -- agentsview pg status
```

Open the dashboard, complete Google SSO, and enter the AgentsView bearer token
when requested. Run one session on the laptop and one inside Paseo; confirm both
machine labels appear after a push. Edit another session and verify incremental
updates, then restart its collector and verify its installation identity persists.
Check other cluster collectors the same way. TCP probes verify the listener only;
verify database freshness through `pg status`, watcher logs at
`/data/pg-watch.log`, and the dashboard. Confirm unauthenticated API access is
rejected and unapproved tailnet devices cannot connect to PostgreSQL.

If sessions are missing, check the source path and watcher logs. For database
connection failures, check ExternalSecret status, Tailscale device approval,
policy grants, and the database pod. The browser token cannot authenticate to
PostgreSQL, and a database password cannot bypass Google SSO.

Run `task lint` then `task dev:validate` before branch testing. Use `task dev:start`
and `task dev:sync` for live testing and always restore main with `task dev:stop`.
