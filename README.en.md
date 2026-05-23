# What is the project?

This project is based on a fully controlled and automated infrastructure deployment on the `Google Cloud platform` cloud platform ensuring security, scalability, monitoring and control by **environments/branches**.


# Infra Live - Environment Index

This README is the environment entry point for the `main` branch.

## Index

- [Dev Environment](#dev-environment)
- [Packer-dev Environment](#packer-dev-environment)

---

## Dev Environment

<details open>
<summary><strong>Show full Dev details</strong></summary>

### Scope

- Terraform: `environments/dev`
- Ansible: `environments/dev/ansible`
- Main workflows:
  - `.github/workflows/Apply-Live.yaml` (`name: terraform-apply`)
  - `.github/workflows/Ansible-Inventory.yaml` (`name: Ansible-Inventory`)

### Structure

```text
environments/dev/
  backend.tf
  providers.tf
  versions.tf
  variables.tf
  terraform.tfvars
  main.tf
  checkov/
    terraform/
  policy/
    terraform-policy/
  ansible/
    site.yml
    requirements.yml
    files/
    templates/
    web/
```

### Terraform (`environments/dev`)

What it creates:

- Ubuntu 22.04 VM (`google_compute_instance`)
- Environment labels (`env = dev`)
- Outputs:
  - `vm_name`
  - `vm_zone`
  - `vm_internal_ip`

Key parameters (`terraform.tfvars`):

- `project_id`, `region`, `zone`
- `machine_type`
- `disk_size_gb`
- `create_public_ip`
- `vm_service_account`

Technical note:

- `machine_type` is defined directly through a variable, for example `e2-standard-2`.

### Ansible (`environments/dev/ansible`)

What it applies:

- Host bootstrap/configuration
- Monitoring/web stack via compose template
- Prometheus, Alertmanager, Grafana, and Nginx

Important paths:

- Playbook: `environments/dev/ansible/site.yml`
- Compose template: `environments/dev/ansible/templates/monitoring/docker-compose.yml.j2`
- Prometheus: `environments/dev/ansible/files/monitoring/prometheus/prometheus.yml`
- Alert rules: `environments/dev/ansible/files/monitoring/prometheus/rules/alerts.yml`

### Dev Workflows

#### `Apply-Live.yaml` (`terraform-apply`)

- Main trigger: `push` to `main` with changes in `environments/dev/**`
- Flow: resolve environment -> plan -> approval gate -> apply
- Includes:  
  - `Checkov, Trivy and Conftest (OPA)`  
  - Terraform/TFLint cache
  - `tflint --init` + lint
  - `outputs.json` export
  - `applied-env` artifact for chained workflows

#### `Ansible-Inventory.yaml` (`Ansible-Inventory`)

- Trigger:
  - `workflow_dispatch`
  - `workflow_run` from `terraform-apply` (dev)
- Generates runtime inventory under `ansible-runtime/`
- Discovers VM zone dynamically at runtime
- Supports `debug_mode` for diagnostics
- Executes `environments/dev/ansible/site.yml`

### Applied optimizations

- Dedicated ephemeral runtime path (`ansible-runtime/`)
- On-demand debug mode (`debug_mode`)
- IAP SSH warm-up with retries/backoff
- Terraform/TFLint/Ansible cache
- `pull_policy: if_not_present` in dev Docker services
- `Security checks`in workflow `Apply-Live.yaml`

### Recommended flow

1. Edit `environments/dev/**` or `environments/dev/ansible/**`
2. Push to `main`
3. Run `terraform-apply`
4. Run/chain `Ansible-Inventory`
5. Validate artifacts and final state

Detailed docs:

- [README dev EN](environments/dev/README.en.md)
- [README dev](environments/dev/README.md)

</details>

---

## Packer-dev Environment

<details>
<summary><strong>Show Packer-dev summary</strong></summary>

`packer-dev` is used for base image flow + lab network/VM + related automation.

Paths:

- Terraform net: `environments/packer-dev/terraform-net`
- Packer Ansible: `environments/packer-dev/ansible`
- Packer template: `environments/packer-dev/gcp-ubuntu-2204-iap`

Detailed docs:

- [Terraform net README](environments/packer-dev/terraform-net/README.md)
- [Packer Ansible README](environments/packer-dev/ansible/README.md)
- [Terraform modules README](environments/packer-dev/terraform-net/modules/README.md)

</details>

## Branch Dev

`The main branch` will be updated periodically to show current and old changes to improve documentation. This branch is for `tests`, `validations`, `continuous improvements`, provider updates, optimizations and real scalability while maintaining `FinOps` focus.