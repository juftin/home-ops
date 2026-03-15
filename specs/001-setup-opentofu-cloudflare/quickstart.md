# Quickstart: OpenTofu Cloudflare IaC Foundation

This guide describes the contributor workflow for the initial `cloudflare` IaC category using the
`iac/live` and `iac/modules` structure.

## Prerequisites

- Repository cloned and checked out on branch `001-setup-opentofu-cloudflare`
- Required local secret files available (`age.key`, `kubeconfig`), per repository standards
- `mise` installed

## 1) Bootstrap tools

```bash
mise install
mise exec -- tofu version
```

Expected result: OpenTofu CLI is available via the repository toolchain.

## 2) Confirm expected IaC layout

```text
iac/
├── live/
│   └── cloudflare/
│       └── homelab/
└── modules/
    └── cloudflare/
        └── zone-baseline/
```

Use `modules/` for reusable definitions and `live/` for environment composition.

## 3) Author or update reusable module definitions

In `iac/modules/cloudflare/zone-baseline/`, maintain module interface files:

- `main.tf`
- `variables.tf`
- `outputs.tf`
- `versions.tf`

Keep module inputs environment-agnostic and reusable.

## 4) Author or update live stack composition

In `iac/live/cloudflare/homelab/`, compose modules and environment-specific inputs:

- `main.tf`
- `providers.tf`
- `backend.tf`
- `variables.tf`
- `outputs.tf`

Do not commit local state files or plaintext secrets.

## 5) Validate locally before opening a PR

```bash
task lint
mise exec -- tofu fmt -check -recursive ./iac
mise exec -- tofu validate ./iac/live/cloudflare/homelab
task dev:validate
```

Notes:

- `task lint` enforces repository formatting/hooks.
- `tofu fmt` + `tofu validate` verify IaC syntax and structure.
- `task dev:validate` keeps existing GitOps manifests healthy while this feature evolves.

## 6) Prepare pull request

- Include summary of module/live changes and affected category paths.
- Confirm no state files or plaintext credentials are in diff.
- Ensure all validation commands above pass.
