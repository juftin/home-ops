# Feature Specification: OpenTofu Cloudflare IaC Foundation

**Feature Branch**: `001-setup-opentofu-cloudflare`
**Created**: 2026-03-15
**Status**: Draft
**Input**: User description: "Create an Infrastructure-as-code setup with Terraform (OpenTofu particularly). Use the existing mise configuration for tools downlaods, and use the iac directory for the actual Terraform/Tofu configuration. The terraform directory structure should use a live/ and a modules/ directory structure. There will be categories like "networking", "kubernetes", etc. But we'll start with "cloudflare""

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Establish baseline IaC layout (Priority: P1)

As a platform maintainer, I can initialize a standardized IaC layout in `iac/` with `live/` and `modules/` so that infrastructure work starts from a consistent structure.

**Why this priority**: This is the foundation for all future infrastructure changes; without it, no consistent IaC workflow exists.

**Independent Test**: Can be tested by inspecting the repository structure and confirming both layers exist with an initial `cloudflare` category and clear ownership boundaries.

**Acceptance Scenarios**:

1. **Given** the repository is checked out, **When** a maintainer opens `iac/`, **Then** they find `live/` and `modules/` as top-level directories.
2. **Given** the baseline layout exists, **When** a maintainer reviews category organization, **Then** `cloudflare` is present as the initial category in the relevant structure.

______________________________________________________________________

### User Story 2 - Bootstrap tools consistently (Priority: P2)

As a contributor, I can use the existing mise configuration to install required IaC tooling so that I can run the workflow without manually selecting tool versions.

**Why this priority**: Consistent tooling reduces onboarding friction and avoids environment drift across contributors.

**Independent Test**: Can be tested by onboarding on a clean workstation using only repository instructions and existing mise configuration, then running an initial IaC validation command.

**Acceptance Scenarios**:

1. **Given** a new contributor with no IaC tools installed, **When** they follow the project's documented bootstrap steps, **Then** they can install required tooling through mise and execute an initial IaC validation successfully.

______________________________________________________________________

### User Story 3 - Prepare reusable Cloudflare-first workflow (Priority: P3)

As an infrastructure engineer, I can define Cloudflare-focused reusable components separately from environment-specific definitions so that changes can be reused and scaled to additional categories later.

**Why this priority**: This ensures the first category (`cloudflare`) demonstrates the intended reuse model before expanding to categories like networking or kubernetes.

**Independent Test**: Can be tested by reviewing one reusable component and one environment-specific definition and verifying the environment-specific definition consumes reusable logic rather than duplicating it.

**Acceptance Scenarios**:

1. **Given** reusable and environment-specific IaC artifacts exist for Cloudflare, **When** a reviewer traces configuration ownership, **Then** shared logic is maintained in reusable artifacts and environment files focus on inputs and intent.

______________________________________________________________________

### Edge Cases

- What happens when a contributor adds a new category (for example, `networking`) after `cloudflare`? The structure must allow this without moving or rewriting existing `cloudflare` paths.
- How does the setup handle contributors who have partially installed tooling? The workflow must still provide a deterministic path to a compliant toolset through existing mise configuration.
- What happens when an environment-specific definition references a reusable component incorrectly? The validation process must fail clearly so the issue can be fixed before merge.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The repository MUST provide a single IaC root at `iac/` for OpenTofu/Terraform configuration relevant to this feature.
- **FR-002**: The IaC root MUST include `live/` and `modules/` directories with clearly distinct responsibilities.
- **FR-003**: The initial implementation MUST include `cloudflare` as a supported category in the appropriate IaC structure.
- **FR-004**: Environment-specific configuration in `live/` MUST be able to consume reusable definitions from `modules/` rather than duplicating shared logic.
- **FR-005**: The setup MUST support future category expansion (such as `networking` and `kubernetes`) without requiring restructuring of existing category paths.
- **FR-006**: Tooling setup MUST use the repository's existing mise configuration as the standard mechanism for obtaining required IaC tools.
- **FR-007**: The feature MUST define a documented contributor workflow for initializing tooling and performing at least one local IaC validation action.
- **FR-008**: The feature MUST define clear naming and placement conventions so contributors can determine where new reusable vs. environment-specific IaC artifacts belong.
- **FR-009**: The feature MUST include at least one Cloudflare-focused example slice that demonstrates the intended live/modules relationship.
- **FR-010**: The setup MUST allow validation failures to be detected prior to merge when structure or reusable-component usage does not follow defined conventions.

### Key Entities *(include if feature involves data)*

- **IaC Category**: A domain grouping (for example, `cloudflare`, `networking`, `kubernetes`) that organizes both reusable and environment-specific artifacts.
- **Reusable Definition**: A shared infrastructure building block intended for repeated use across environments.
- **Live Definition**: An environment-specific infrastructure definition that declares intent and inputs while relying on reusable definitions.
- **Toolchain Profile**: The project-defined set of IaC tooling versions and acquisition method used by contributors.

## Assumptions

- The existing mise configuration is the authoritative source for tool installation and version consistency.
- This feature establishes baseline structure and workflow, not full coverage for all future categories.
- Cloudflare is the first category for proving the pattern; additional categories will follow the same model.
- Credential provisioning and secret management for provider authentication are handled by existing project practices and are not expanded by this feature.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A new contributor can complete IaC tool bootstrap and run a first local validation workflow in 15 minutes or less using repository documentation only.
- **SC-002**: 100% of IaC artifacts introduced by this feature are placed under either `iac/live/` or `iac/modules/` with no orphan configuration paths.
- **SC-003**: Reviewers can identify whether a change is reusable or environment-specific from file placement and naming alone in at least 95% of sampled changes.
- **SC-004**: At least one complete Cloudflare example slice can be validated end-to-end by maintainers without requiring directory restructuring.
- **SC-005**: Adding a second category following the documented conventions can be completed without changing existing Cloudflare directory structure.
