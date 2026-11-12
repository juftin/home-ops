# Feature Specification: Self-Hosted GitHub Actions Runner

**Feature Branch**: `006-github-actions-runner`
**Created**: 2026-10-16
**Status**: Draft
**Input**: User description: "Using spec-kit - let's create our own self-hosted github runner. I want to use https://github.com/actions/actions-runner-controller"

## Clarifications

### Session 2026-10-16

- Q: Where should the initial runner be available? → A: `juftin/home-ops` only.
- Q: What should the first runner support? → A: Shell commands, JavaScript actions, Docker builds, container actions, and service containers.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Execute Repository Jobs (Priority: P1)

As the repository maintainer, I want to select a self-hosted runner for trusted workflows in
`juftin/home-ops` so that I can execute CI jobs on my own infrastructure.

**Why this priority**: Successful execution, including the requested container capabilities,
is the minimum useful feature.

**Independent Test**: Manually dispatch smoke jobs from the default branch covering checkout,
shell commands, a JavaScript action, a Docker build and run, a container action, and job/service containers.

**Acceptance Scenarios**:

1. **Given** the service is healthy, **When** a maintainer dispatches a workflow targeting its
   documented runner name, **Then** the job executes in the homelab and reports its logs and result in GitHub.
2. **Given** a checked-out repository, **When** a job runs shell commands and a JavaScript action,
   **Then** they succeed without interactive runner preparation.
3. **Given** a small Dockerfile, **When** a job builds and runs its image, **Then** the container
   returns the expected output without external registry write credentials.
4. **Given** a workflow uses a container action, **When** it executes, **Then** inputs, workspace
   access, outputs, and exit status behave as expected.
5. **Given** a job declares a service container with a health check, **When** it becomes healthy,
   **Then** job steps can connect using the documented workflow connection settings.
6. **Given** a workflow declares a job container and a service container, **When** its steps run,
   **Then** checkout, shell execution, and service connectivity succeed inside the job container.
7. **Given** an existing workflow targets GitHub-hosted runners, **When** it runs, **Then** its
   runner selection is unaffected by adding the service.

### User Story 2 - Scale Without Retaining Job State (Priority: P2)

As the homelab operator, I want fresh runners to appear for queued work and disappear afterward
so that CI shares limited homelab resources predictably.

**Why this priority**: Bounded concurrency and cleanup protect the shared, single-node cluster.

**Independent Test**: Queue three independent jobs against a two-runner limit, record concurrency
and runner identities, and inspect cleanup after completion and cancellation.

**Acceptance Scenarios**:

1. **Given** zero idle runners, **When** a trusted job is queued, **Then** a fresh runner starts and accepts it.
2. **Given** a concurrency limit of two, **When** three jobs are queued, **Then** at most two
   execute simultaneously and the third executes after capacity becomes available.
3. **Given** one job writes a workspace marker and creates container state, **When** the next
   job starts, **Then** it receives a different runner and cannot retrieve that state.
4. **Given** all jobs finish or are cancelled, **When** cleanup completes, **Then** no job
   runners, job containers, or temporary workspaces remain; control components may remain running.

### User Story 3 - Operate Through GitOps (Priority: P2)

As the homelab operator, I want documented setup, credential rotation, failure diagnosis, and
removal so that I can maintain the runner using the repository's existing workflows.

**Why this priority**: Registration and execution failures must be recoverable and visible.

**Independent Test**: Follow the setup guide, inspect a simulated authentication failure,
rotate the credential, and complete another smoke job.

**Acceptance Scenarios**:

1. **Given** external credentials are provisioned as documented, **When** desired configuration
   is reconciled, **Then** the service becomes available without manual resource applies.
2. **Given** a registration credential is missing, expired, or revoked, **When** registration
   fails, **Then** secret synchronization status and control-component logs identify the cause
   without exposing the credential.
3. **Given** credentials have been rotated at their source, **When** documented refresh and
   recovery steps finish, **Then** a new smoke job succeeds.
4. **Given** resource pressure or connectivity prevents startup, **When** the operator inspects
   status and retained logs, **Then** the blocking condition is visible.
5. **Given** the service is removed through GitOps, **When** reconciliation and documented cleanup
   finish, **Then** no runner remains available for new jobs and existing hosted CI remains usable.

### Edge Cases

- Excess jobs remain queued; resource pressure must not trigger unlimited scaling.
- GitHub connectivity failures prevent new work and produce diagnosable errors. Interrupted jobs
  are not promised automatic replay.
- A runner or node failure may fail an active job; subsequent jobs must receive fresh runners
  after infrastructure recovers.
- Cancellation must clean up container workloads and temporary storage as well as runners.
- Fork pull requests must not select homelab runners or access homelab credentials. Maintainer
  approval of a fork workflow alone does not make its code trusted.
- A container build exceeding its storage or memory budget must fail visibly without unbounded
  host resource consumption.
- An incorrect runner selector leaves work queued; documentation must explain how to distinguish
  this from unavailable capacity.
- Failed jobs must leave retained logs after their runners are deleted.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The service MUST use Actions Runner Controller and register runners exclusively
  for `juftin/home-ops` in the initial release.
- **FR-002**: Maintainers MUST be able to select a documented, stable workflow runner name and
  dispatch smoke jobs from the default branch.
- **FR-003**: Runners MUST support checkout, shell steps, JavaScript actions, Docker builds and
  local container execution, container actions, job containers, and service containers,
  including workspace access and service networking.
- **FR-004**: Each runner MUST execute at most one job. Its workspace, container runtime state,
  and temporary credentials MUST be discarded after completion or cancellation.
- **FR-005**: The service MUST default to zero idle runners and at most two concurrent jobs.
  Operators MUST be able to change both limits declaratively; excess work MUST remain queued.
- **FR-006**: Runners and their container workloads MUST have explicit CPU, memory, and temporary
  storage budgets bounding aggregate usage at the configured concurrency limit.
- **FR-007**: Control components and job workloads MUST use separate namespaces and minimum
  required permissions. Jobs MUST NOT receive registration credentials, cluster administration
  credentials, host container sockets, host paths, or host networking.
- **FR-008**: Job network access MUST be restricted to declared dependencies, including name
  resolution and required external endpoints. Unrelated homelab services and private LAN
  destinations MUST be inaccessible. Any required container execution privileges and their
  residual isolation limitations MUST be documented.
- **FR-009**: Registration credentials MUST come from the existing external secret management
  system. Plaintext secrets MUST NOT appear in Git, manifests, workflows, or logs. Documentation
  MUST identify the selected authentication method, minimum permissions, and rotation procedure.
- **FR-010**: Installation, updates, and removal MUST follow the existing GitOps app structure,
  offline rendering checks, and dependency update conventions.
- **FR-011**: Initial homelab workflow execution MUST be limited to maintainer-controlled code
  on the default branch through manual dispatch or default-branch push triggers. Existing PR
  checks MUST continue using GitHub-hosted runners. Fork code MUST NOT execute on homelab runners.
- **FR-012**: Operators MUST be able to diagnose registration, listener, scheduling, and job
  failures using read-only status and logs. Control and runner logs MUST reach the existing
  central log store and survive runner deletion for its configured retention period.
- **FR-013**: Documentation MUST cover prerequisites, runner selection, container smoke tests,
  scaling, resource budgets, trust boundaries, credential rotation, recovery, and removal.
  The component inventory and architecture documentation MUST include the implemented service.

### Key Entities

- **Runner scale set**: The repository's selectable pool of ephemeral runners, identified by its
  stable workflow name, repository scope, and capacity limits.
- **Job runner**: A disposable environment assigned to one job, including its workspace and
  associated build, action, job, and service containers.
- **Registration credential**: Externally managed authentication for registering runners,
  separate from temporary credentials available to individual jobs.
- **Trusted workflow**: Maintainer-controlled workflow and code eligible to execute within the
  documented homelab trust boundary.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Three consecutive manually dispatched smoke runs succeed with logs and results
  visible in GitHub. Each covers checkout, shell steps, a JavaScript action, an image build and
  run, a container action, and job/service container connectivity.
- **SC-002**: With dependencies healthy, sufficient capacity, and images already available,
  each of three sequential smoke jobs starts within five minutes of queuing.
- **SC-003**: Three queued jobs never exceed two simultaneous executions, all complete, and
  leave zero job runners and containers within five minutes of final completion or cancellation.
- **SC-004**: A second job cannot retrieve the first job's workspace marker or container state.
  Isolation checks confirm jobs cannot retrieve registration credentials or connect to an
  unrelated homelab service or private LAN destination.
- **SC-005**: Failed job logs remain searchable after runner deletion for the existing central
  log retention period. Registration failures are diagnosable without reading secret values.
- **SC-006**: Following the credential rotation procedure restores successful smoke execution.
  Removing the service leaves existing PR checks operational.
- **SC-007**: All introduced or modified workflows selecting the homelab runner exclude PR
  triggers and arbitrary user-supplied code refs; existing fork PR checks use hosted runners.

## Assumptions & Dependencies

- Existing Talos, GitOps, external secret management, networking, and central logging are platform
  dependencies. No new node or cluster is included.
- Zero idle runners and two concurrent jobs are proposed defaults for the documented single-node
  cluster. Planning must size resource budgets against available capacity.
- The operator will provision external GitHub authentication and a secret manager item following
  documented instructions. Credentials are not needed during specification or planning.
- Planning will select and validate a container execution mode compatible with Talos and every
  requested workload capability, documenting required privileges before implementation.
- Persistent build caches, custom runner image pipelines, multi-architecture builds,
  organization-wide runners, and migrating existing PR checks are outside the initial scope.
- Image publication is optional future workflow configuration; initial smoke tests require no
  external registry write credentials.
- Ephemeral runners in a shared cluster are not a strong boundary for hostile code. The initial
  trust model permits only maintainer-controlled jobs; stronger isolation requires separate work.

## References

- [Actions Runner Controller](https://github.com/actions/actions-runner-controller): requested
  project; new deployments use runner scale sets rather than legacy autoscaling modes.
- [Deploying runner scale sets](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/deploy-runner-scale-sets):
  deployment, scaling, container execution, and namespace isolation guidance.
- [Authenticating ARC](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/authenticate-to-the-api):
  authentication choices and minimum permissions to evaluate during planning.
