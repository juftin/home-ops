# Data Model: Envoy Authentik Authentication Migration

## Entity: AuthenticationMode

- **Description**: Cluster-wide selector for authentication behavior.
- **Fields**:
  - `mode` (enum: `authentik`, `legacy`)
  - `effectiveAt` (datetime)
  - `changedBy` (string, operator identity)
- **Validation Rules**:
  - Exactly one active mode at any time.
  - Mode change must apply to all protected routes simultaneously.
- **State Transitions**:
  - `legacy -> authentik`
  - `authentik -> legacy`

## Entity: ProtectedRoute

- **Description**: Route that requires authentication/authorization before access.
- **Fields**:
  - `routeId` (string, unique within cluster)
  - `hostname` (string)
  - `pathPattern` (string)
  - `requiresAuth` (boolean)
  - `requiredGroups` (list<string>)
- **Validation Rules**:
  - Protected routes must be evaluated by the active AuthenticationMode.
  - Routes requiring group checks must define at least one required group.

## Entity: IdentitySubject

- **Description**: Authenticated principal evaluated for access.
- **Fields**:
  - `subjectId` (string, stable principal id)
  - `email` (string)
  - `groups` (list<string>)
  - `emailVerified` (boolean)
- **Validation Rules**:
  - `emailVerified` must be true for successful authorization when email-based trust is required.

## Entity: AuthorizationDecision

- **Description**: Per-request allow/deny result returned from centralized auth evaluation.
- **Fields**:
  - `decisionId` (string)
  - `timestamp` (datetime)
  - `routeId` (string, references ProtectedRoute)
  - `subjectId` (string, references IdentitySubject)
  - `outcome` (enum: `allow`, `deny`)
  - `denialReason` (string, required when outcome=`deny`)
  - `sourceMode` (enum: `authentik`, `legacy`)
- **Validation Rules**:
  - Denial reason required for denied decisions.
  - Missing decision from upstream auth source must be recorded as deny-equivalent failure context.

## Relationships

- `AuthenticationMode` governs evaluation behavior for many `ProtectedRoute` records.
- `IdentitySubject` can produce many `AuthorizationDecision` records.
- `ProtectedRoute` can have many `AuthorizationDecision` records.

## Scale Assumptions

- Designed for single-cluster homelab traffic with operator-managed route inventory.
- Model supports incremental route growth without changing core entities.
