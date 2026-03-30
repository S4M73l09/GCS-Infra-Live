# Infra Live - Environment Index

This README is the environment entry point for the `main` branch.

## Index

- [Dev Environment](#dev-environment)
- [Global Environment](#global-environment)

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
  - `vm_external_ip`

Key parameters (`terraform.tfvars`):

- `project_id`, `region`, `zone`
- `series`, `vcpus`, `memory_mb`
- `disk_size_gb`
- `create_public_ip`

### Ansible (`environments/dev/ansible`)

What it applies:

- Host bootstrap/configuration
- Monitoring/web stack via compose template
- Prometheus, Alertmanager, Grafana, Nginx and Blackbox

Important paths:

- Playbook: `environments/dev/ansible/site.yml`
- Compose template: `environments/dev/ansible/templates/monitoring/docker-compose.yml.j2`
- Prometheus: `environments/dev/ansible/files/monitoring/prometheus/prometheus.yml`
- Alert rules: `environments/dev/ansible/files/monitoring/prometheus/rules/alerts.yml`

### Dev Workflows

#### `Apply-Live.yaml` (`terraform-apply`)

- Main trigger: `push` to `main` with changes in `environments/dev/**`
- `workflow_dispatch` restricted to `dev`
- Flow: resolve environment -> plan -> approval gate -> apply
- Includes:
  - Terraform/TFLint cache
  - `tflint --init` + lint
  - `outputs.json` export
  - `applied-env` and `applied-vm-zone` artifacts

#### `Ansible-Inventory.yaml` (`Ansible-Inventory`)

- Trigger:
  - `workflow_dispatch`
  - `workflow_run` from `terraform-apply` (main)
- Generates runtime inventory under `ansible-runtime/`
- IAP SSH warm-up with retries/backoff
- Executes `environments/dev/ansible/site.yml`

### Applied optimizations

- Dedicated ephemeral runtime path (`ansible-runtime/`)
- On-demand debug mode (`debug_mode`)
- IAP SSH warm-up with retries/backoff
- Terraform/TFLint/Ansible cache
- `pull_policy: if_not_present` in Docker services

### Recommended flow

1. Edit `environments/dev/**` or `environments/dev/ansible/**`
2. Push to `main`
3. Run `terraform-apply`
4. Run/chain `Ansible-Inventory`
5. Validate artifacts and final state

Detailed docs:

- [README dev](environments/dev/README.md)
- [README dev EN](environments/dev/README.en.md)

</details>

## Global Environment

<details>
<summary><strong>Show Global summary</strong></summary>

`global` contains shared/base resources (for example base networking, common IAM and reusable components).

Path:

- `environments/global`

</details>
