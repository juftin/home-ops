# Workflow Contract

## Selection and trust

- Repository: `juftin/home-ops`.
- Runner selector: `runs-on: home-ops`; use the scale-set name directly.
- Initial trigger: `workflow_dispatch` only.
- Every job selecting this runner checks `github.ref == 'refs/heads/main'` before it is scheduled.
- Checkout explicitly selects `main`, disables credential persistence, and accepts no ref input.
- Workflow permissions: `contents: read`; no registration credential or cluster secret is provided.
- Pin action commit SHAs using existing repository style. Set finite job timeouts.
- Existing PR quality/render checks continue on `ubuntu-latest`.

A manual dispatch on another branch is skipped. No PR trigger, `pull_request_target`, downloaded
untrusted artifacts, arbitrary code refs, or user-supplied shell commands may enter this workflow.
The runner selector is not an authorization barrier: maintainers must preserve the trust rule in
future workflow changes. GitHub fork approval by itself is insufficient.

## Smoke jobs

| Job                        | Required observations                                                                                                                       |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Shell and build            | Checkout, shell output, JavaScript action, Docker version/info, build a local synthetic Dockerfile, run image and assert output             |
| Container action           | Local Docker action receives input, accesses workspace, writes expected output through GitHub output file, and propagates failure correctly |
| Service from host job      | Health-checked synthetic service reachable through an explicitly published localhost port                                                   |
| Job container plus service | Containerized steps run checkout/shell and access service by service name and container port                                                |

Use public images only; no registry publication. Include no real application data or secrets.
The local action and Dockerfile live under `.github/runner-smoke/`, outside app discovery.

## Later acceptance exercises

- Dispatch three times successfully; collect job/runner identities, queue/start/finish times.
- Queue three independent jobs without workflow-level serialization; maximum two execute at once.
- Verify both normal completion and cancellation remove runners and nested runtime state.
- Check workspace/container marker absence in a subsequent fresh job.
- Probe a known unrelated cluster service, private LAN destination, and API from runner and
  nested containers using bounded timeouts; all must fail while required external HTTPS works.
- Verify no registration secret reference, API token mount, host mount, or host network in live pods.
- Verify cgroup placement/resource accounting for nested containers without intentionally exhausting
  the shared node. Any destructive pressure experiment needs a separately controlled environment.
- Produce a benign failed job; retain GitHub step logs and find matching diagnostic records in
  Loki after the pod is deleted. Do not claim full step-output mirroring.
- Rotate registration credentials externally, recover through the documented procedure, run again.

Manual dispatch requires the workflow on the default branch. Run workflow acceptance after merge;
branch testing can verify Kubernetes readiness beforehand without removing the main-branch guard.
