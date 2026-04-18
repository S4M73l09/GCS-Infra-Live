# Infra Live - Environment Index

This README is the environment entry point for the `staging` branch.

## Index

- [Staging Environment](#staging-environment)
- [Packer-dev Environment](#packer-dev-environment)

---

## Staging Environment

<details open>
<summary><strong>Show full Staging details</strong></summary>

### Scope

- Terraform: `environments/staging`
- Ansible: `environments/staging/ansible`
- Main workflows:
  - `.github/workflows/Apply-Live.yaml` (`name: terraform-apply`)
  - `.github/workflows/Ansible-Inventory.yaml` (`name: Ansible-Inventory`)

### Structure

```text
environments/staging/
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

### Terraform (`environments/staging`)

What it creates:

- Ubuntu 22.04 VM (`google_compute_instance`)
- Environment labels (`env = staging`)
- Outputs:
  - `vm_name`
  - `vm_zone`
  - `vm_internal_ip`
  - `vm_external_ip`

Key parameters (`terraform.tfvars`):

- `project_id`, `region`, `zone`
- `series`, `vcpus`, `memory_mb`
- `disk_size_gb`
- `create_public_ip`

Technical note:

- Custom `machine_type` is built in `main.tf` as:
  - `${var.series}-custom-${var.vcpus}-${var.memory_mb}`

### Ansible (`environments/staging/ansible`)

What it applies:

- Host bootstrap/configuration
- Monitoring/web stack via compose template
- Prometheus, Alertmanager, Grafana, and Nginx

Important paths:

- Playbook: `environments/staging/ansible/site.yml`
- Compose template: `environments/staging/ansible/templates/monitoring/docker-compose.yml.j2`
- Prometheus: `environments/staging/ansible/files/monitoring/prometheus/prometheus.yml`
- Alert rules: `environments/staging/ansible/files/monitoring/prometheus/rules/alerts.yml`

### Staging Workflows

#### `Apply-Live.yaml` (`terraform-apply`)

- Main trigger: `push` to `staging` with changes in `environments/staging/**`
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
  - `workflow_run` from `terraform-apply` (staging)
- Generates runtime inventory under `ansible-runtime/`
- Discovers VM zone dynamically at runtime
- Supports `debug_mode` for diagnostics
- Executes `environments/staging/ansible/site.yml`

### Applied optimizations

- Dedicated ephemeral runtime path (`ansible-runtime/`)
- On-demand debug mode (`debug_mode`)
- IAP SSH warm-up with retries/backoff
- Terraform/TFLint/Ansible cache
- `pull_policy: if_not_present` in staging Docker services
- `Security checks`in workflow `Apply-Live.yaml`

### Recommended flow

1. Edit `environments/staging/**` or `environments/staging/ansible/**`
2. Push to `staging`
3. Run `terraform-apply`
4. Run/chain `Ansible-Inventory`
5. Validate artifacts and final state

Detailed docs:

- [README staging EN](environments/staging/README.en.md)
- [README staging](environments/staging/README.md)

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

## Branch Staging

`The staging branch` will be updated periodically to show current and old changes to improve documentation. This branch is for `tests`, `validations`, `continuous improvements`, provider updates, optimizations and real scalability while maintaining `FinOps` focus.