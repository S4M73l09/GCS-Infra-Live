# `dev` Environment

This README documents **everything under `environments/dev/`** and how it is operated in CI/CD.

## Index

- [Block 1: Terraform](#block-1-terraform)
- [Block 2: Ansible](#block-2-ansible)
- [Block 3: Workflows using this path](#block-3-workflows-using-this-path)

## Block 1: Terraform

### Paths

- `environments/dev/main.tf`
- `environments/dev/variables.tf`
- `environments/dev/providers.tf`
- `environments/dev/versions.tf`
- `environments/dev/backend.tf`
- `environments/dev/terraform.tfvars`
- `environments/dev/.tflint.hcl`

### What it deploys

- One Ubuntu 22.04 VM on GCP (`google_compute_instance.ubuntu`).
- Custom `machine_type` built from `series + vcpus + memory_mb`.
- Configurable boot disk (`disk_size_gb`, `pd-balanced`).
- Labels including `env = dev`.
- `iap-ssh` network tag for IAP access.
- Optional public IP through `create_public_ip`.

### Main outputs

- `vm_name`
- `vm_zone`
- `vm_internal_ip`
- `vm_external_ip`

### Applied optimization and hardening

- Remote GCS backend (`backend.tf`) for centralized state.
- Terraform/Provider version pinning (`versions.tf`).
- TFLint enforcement (`.tflint.hcl`) in pipeline.
- Terraform plugin cache keyed by environment lockfile to speed up `init`.
- Dynamic `vm_zone` export after `apply` for chained automation.

## Block 2: Ansible

### Paths

- `environments/dev/ansible/site.yml`
- `environments/dev/ansible/requirements.yml`
- `environments/dev/ansible/files/**`
- `environments/dev/ansible/templates/**`
- `environments/dev/ansible/web/**`

### What it configures

- Docker + Compose plugin installation on the VM.
- Monitoring/web stack deployment:
  - Prometheus
  - Alertmanager
  - Node Exporter
  - Grafana
  - Blackbox Exporter
  - Nginx
- Prometheus/Grafana files and compose/alertmanager templates provisioning.

### Applied optimization

- `gather_facts: true` so `ansible_facts` is explicitly available.
- `pull_policy: if_not_present` in compose services to reduce unnecessary pulls.
- Resource limits on key services (e.g. Prometheus/Grafana).
- Container log rotation (`max-size`, `max-file`).

### Runtime (on-the-fly)

The workflow does not rely on persistent inventory. It generates temporary runtime files under `ansible-runtime/`:

- `hosts.ini`
- `ansible.cfg`
- `hosts_with_zones.list`
- ephemeral SSH key

## Block 3: Workflows using this path

### 1) `.github/workflows/Apply-Live.yaml` (`name: terraform-apply`)

- Main trigger: `push` on `main` branch with changes in `environments/dev/**`.
- Also supports `workflow_dispatch` (restricted to `dev`).
- Flow: `changes -> plan -> approve_gate -> apply -> publish-env-artifact`.
- Published artifacts:
  - `tfplan` (`tfplan.bin`, `tfplan.txt`, `tfplan.json`)
  - `terraform-outputs-dev` (`outputs.json`)
  - `applied-vm-zone` (`vm_zone.txt`)
  - `applied-env` (`env.txt`)

### 2) `.github/workflows/Ansible-Inventory.yaml` (`name: Ansible-Inventory`)

- Trigger:
  - `workflow_dispatch`
  - `workflow_run` from `terraform-apply` (when it ends with `success`) on `main`
- Resolves environment from `env.txt` or manual input.
- Starts environment VMs if they are stopped (by `env` label).
- Generates runtime inventory and runs:
  - `ansible-playbook -i ansible-runtime/hosts.ini environments/dev/ansible/site.yml`

### Applied optimization in Ansible workflow

- `debug_mode` input to enable diagnostic steps on demand.
- Dynamic branch checkout (`head_branch` on `workflow_run`).
- IAP SSH warm-up with retries/backoff to reduce intermittent failures.
- collections/pip cache key based on real dependency files.

## Recommended operation flow

1. Change Terraform or Ansible under `environments/dev/**`.
2. Push to `main` branch.
3. Run/approve `terraform-apply`.
4. Run (or chain) `Ansible-Inventory`.
5. Review artifacts and final service state.
