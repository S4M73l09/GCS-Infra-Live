# `staging` Environment

This README documents **everything under `environments/staging/`** and how it is operated in CI/CD.

## Index

- [Block 1: Terraform](#block-1-terraform)
- [Block 2: Ansible](#block-2-ansible)
- [Block 3: Workflows using this path](#block-3-workflows-using-this-path)

## Block 1: Terraform

### Paths

- `environments/staging/main.tf`
- `environments/staging/variables.tf`
- `environments/staging/providers.tf`
- `environments/staging/versions.tf`
- `environments/staging/backend.tf`
- `environments/staging/terraform.tfvars`
- `environments/staging/.tflint.hcl`

### What it deploys

- One Ubuntu 22.04 VM on GCP (`google_compute_instance.ubuntu`).
- Custom `machine_type` built from `series + vcpus + memory_mb`.
- Configurable boot disk (`disk_size_gb`, `pd-balanced`).
- Labels including `env = staging`.
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

### Policy as Code (OPA/Conftest)

- Policy folder: `environments/staging/policy/terraform-policy`.
- Static policy checks on `.tf`:
  - `security.rego` (default SA, secure boot, SSH-open firewall checks).
  - `labels.rego` (required labels and `env=staging`).
- Runtime checks on resolved plan (`tfplan.json`):
  - `plan-security.rego` (validation over `resource_changes`).
- `finops.rego` is oriented to plan-based checks (not unresolved source values).

### Policy as Code (Custom Checkov)

- Custom checks folder: `environments/staging/checkov/terraform`.
- Pipeline integration (`security_checks`):
  - `bridgecrewio/checkov-action@v12`
  - `external_checks_dirs: ${{ needs.changes.outputs.dir }}/checkov/terraform`
- Current custom checks:
  - `check_vm_no_default_sa.py`: fails if VM uses `default` SA or no SA is defined.
  - `check_vm_secure_boot.py`: enforces `shielded_instance_config.enable_secure_boot = true`.
  - `check_firewall_no_ssh_open.py`: blocks ingress SSH (`22`) from `0.0.0.0/0`.
- Optional local syntax validation:
  - `python3 -m py_compile environments/staging/checkov/terraform/*.py`

## Block 2: Ansible

### Paths

- `environments/staging/ansible/site.yml`
- `environments/staging/ansible/requirements.yml`
- `environments/staging/ansible/files/**`
- `environments/staging/ansible/templates/**`
- `environments/staging/ansible/web/**`

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

### Maintenance File

This file `system-maintenance.yml` is use for update packages in `Linux` and maintenance of critical files or vulnerability.

This is activated by the workflow `Ansible-System-Maintenance.yaml` which generates everything necessary Runtime.

## Block 3: Workflows using this path

### 1) `.github/workflows/Apply-Live.yaml` (`name: terraform-apply`)

- Main trigger: `push` on `staging` branch with changes in `environments/staging/**`.
- Also supports `workflow_dispatch` (restricted to `staging`).
- Flow: `changes -> security_checks -> plan -> approve_gate -> apply -> publish-env-artifact`.
- `security_checks` runs static controls for the environment:
  - `tflint`
  - `checkov`
  - `trivy config`
  - `trivy fs`
- `plan` generates `tfplan.json` and runs `conftest` against `policy/terraform-policy`.
- Published artifacts:
  - `tfplan` (`tfplan.bin`, `tfplan.txt`, `tfplan.json`)
  - `terraform-outputs-staging` (`outputs.json`)
  - `applied-vm-zone` (`vm_zone.txt`)
  - `applied-env` (`env.txt`)

### 2) `.github/workflows/Ansible-Inventory.yaml` (`name: Ansible-Inventory`)

- Trigger:
  - `workflow_dispatch`
  - `workflow_run` from `terraform-apply` (when it ends with `success`)
- Resolves environment from `env.txt` or manual input.
- Starts environment VMs if they are stopped (by `env` label).
- Generates runtime inventory and runs:
  - `ansible-playbook -i ansible-runtime/hosts.ini environments/staging/ansible/site.yml`

### Applied optimization in Ansible workflow

- `debug_mode` input to enable diagnostic steps on demand.
- Dynamic branch checkout (`head_branch` on `workflow_run`).
- IAP SSH warm-up with retries/backoff to reduce intermittent failures.
- collections/pip cache key based on real dependency files.

## Recommended operation flow

1. Change Terraform or Ansible under `environments/staging/**`.
2. Validate static policies locally (optional, recommended):
   - `conftest test environments/staging/*.tf -p environments/staging/policy/terraform-policy`
3. Push to `staging` branch.
4. Run/approve `terraform-apply`.
5. Run (or chain) `Ansible-Inventory`.
6. Review artifacts and final service state.
