# Data Model: Authentik Cluster Authentication

## Entity: AuthentikDeployment

- **Description**: In-cluster identity provider deployment managed through GitOps resources.
- **Fields**:
  - `namespace` (string, required, default `security`)
  - `releaseName` (string, required)
  - `enabled` (boolean, required)
  - `bootstrapSecretRefs` (list[string], required)
  - `status` (enum: `pending`, `ready`, `failed`, required)
- **Validation Rules**:
  - Deployment cannot transition to `ready` without all required bootstrap secret references.
  - `releaseName` must be unique within the namespace.

## Entity: ProtectedRoute

- **Description**: Public app entrypoint that must be authenticated by one configured path.
- **Fields**:
  - `routeId` (string, required, unique)
  - `hostname` (string, required)
  - `pathPrefix` (string, optional, default `/`)
  - `namespace` (string, required)
  - `serviceName` (string, required)
  - `authPath` (enum: `authentik`, `google-proxy`, required)
  - `migrationPhase` (enum: `legacy`, `pilot`, `migrated`, required)
  - `protected` (boolean, required; if true then `authPath` required)
- **Validation Rules**:
  - `routeId` must be globally unique in feature scope.
  - Protected routes must have exactly one `authPath`.
  - `migrationPhase=pilot|migrated` implies `authPath=authentik`.

## Entity: AuthenticationPath

- **Description**: Named authentication provider route policy used by gateway.
- **Fields**:
  - `name` (enum: `authentik`, `google-proxy`)
  - `availabilityState` (enum: `healthy`, `degraded`, `unavailable`)
  - `callbackHost` (string, required)
  - `enforcementMode` (enum: `required`, `disabled`)
- **Validation Rules**:
  - `name` unique by definition.
  - `callbackHost` must resolve to explicit ingress rule.

## Entity: AuthenticationOutcomeRecord

- **Description**: Audit/ops record of auth decision for a protected route request.
- **Fields**:
  - `eventId` (string, required, unique)
  - `occurredAt` (timestamp, required)
  - `routeId` (string, required, foreign key -> ProtectedRoute.routeId)
  - `authPath` (enum: `authentik`, `google-proxy`, required)
  - `outcome` (enum: `allowed`, `denied`, `error`, required)
  - `reasonCode` (string, required)
- **Validation Rules**:
  - Records retained/queryable for >=30 days.
  - `authPath` must match route assignment at event time.

## Relationships

- One `AuthentikDeployment` provides the `AuthenticationPath` named `authentik`.
- One `ProtectedRoute` references one active `AuthenticationPath`.
- One `ProtectedRoute` has many `AuthenticationOutcomeRecord` entries.

## State Transitions

- **AuthentikDeployment.status**:
  - `pending` -> `ready` when deployment and bootstrap dependencies are satisfied.
  - `pending` -> `failed` when required secrets or startup dependencies are missing.
  - `failed` -> `pending` when missing prerequisites are corrected.
- **ProtectedRoute.migrationPhase**:
  - `legacy` -> `pilot` when included in phased Authentik subset.
  - `pilot` -> `migrated` when rollout criteria are met.
  - `pilot` -> `legacy` allowed for rollback.
- **AuthenticationPath.availabilityState**:
  - `healthy` \<-> `degraded` \<-> `unavailable` based on provider/gateway health signals.
