# Data Model: OpenTofu Cloudflare IaC Foundation

## Entities

### 1) ToolchainProfile

- **Description**: Defines how contributors obtain and run required IaC tools.
- **Fields**:
  - `manager` (string, required): Tool manager identifier (`mise`)
  - `tools` (list, required): Required tool entries with pinned versions
  - `bootstrapCommand` (string, required): Standard install command
  - `validationCommands` (list, required): Standard pre-merge validation sequence
- **Validation Rules**:
  - `manager` must match repository standard.
  - All required IaC tools must be represented in `tools`.
  - Commands must be executable from repository root.

### 2) IacCategory

- **Description**: Domain grouping for infrastructure definitions (starting with `cloudflare`).
- **Fields**:
  - `name` (string, required): Category slug
  - `modulePath` (string, required): Path under `iac/modules`
  - `livePath` (string, required): Path under `iac/live`
  - `status` (enum, required): `planned | active | deprecated`
- **Validation Rules**:
  - `name` must be lowercase and hyphen-safe.
  - `modulePath` and `livePath` must remain within `iac/`.
  - Category names must be unique.

### 3) ModuleDefinition

- **Description**: Reusable OpenTofu building block in a category.
- **Fields**:
  - `category` (string, required)
  - `name` (string, required)
  - `inputs` (list, required): Declared variable interfaces
  - `outputs` (list, optional): Declared output interfaces
  - `versionPolicy` (string, required): Provider/runtime compatibility rules
- **Validation Rules**:
  - Must expose only documented input/output interfaces.
  - Must not hardcode environment-only values.
  - Must be consumable from at least one live stack.

### 4) LiveStack

- **Description**: Environment-specific composition of modules and inputs.
- **Fields**:
  - `category` (string, required)
  - `environment` (string, required): First value `homelab`
  - `moduleRefs` (list, required): Module links used by this stack
  - `backendStrategy` (string, required): Remote-state strategy descriptor
  - `variablesSource` (list, required): Input source definitions
- **Validation Rules**:
  - Must reference reusable modules for shared logic.
  - Must not contain committed sensitive data.
  - Must define explicit backend behavior.

### 5) ValidationRun

- **Description**: Captures outcome of contributor validation execution.
- **Fields**:
  - `scope` (enum, required): `format | validate | full`
  - `status` (enum, required): `passed | failed`
  - `startedAt` (datetime, required)
  - `finishedAt` (datetime, required)
  - `errors` (list, optional)
- **Validation Rules**:
  - `finishedAt` must be later than `startedAt`.
  - `errors` required when `status = failed`.

## Relationships

- `IacCategory` 1-to-many `ModuleDefinition`
- `IacCategory` 1-to-many `LiveStack`
- `LiveStack` many-to-many `ModuleDefinition` (via `moduleRefs`)
- `ToolchainProfile` governs execution context for `ValidationRun`

## State Transitions

### IacCategory Lifecycle

`planned -> active -> deprecated`

- `planned -> active`: Triggered when both module and live paths are implemented and pass validation.
- `active -> deprecated`: Triggered when category is superseded and no longer receives new stacks.

### ValidationRun Lifecycle

`queued -> running -> passed | failed`

- `running -> failed`: Any formatting/validation command returns non-zero exit code.
- `running -> passed`: All required checks complete successfully.
