# Global Terraform (project resources)

This stack contains **project-level global resources** shared by all environments (dev/staging). It should not be duplicated per environment.

## Managed resources
- Project APIs: `compute.googleapis.com`, `oslogin.googleapis.com`.
- Project metadata (managed outside Terraform):
  - `enable-oslogin`
  - `block-project-ssh-keys`
- OS Login IAM:
  - `roles/compute.osLogin`
  - `roles/compute.osAdminLogin`
- IAP SSH firewall: `allow-iap-ssh`.
- Cloud Router + Cloud NAT (egress without public IP).

## What was isolated here
These resources were previously defined inside environment stacks and were isolated to avoid collisions and duplicated state:
- Project metadata (kept outside this stack).
- OS Login/OS Admin IAM.
- IAP firewall.
- Router + NAT.

## What was imported
Existing project resources were imported into this global state to avoid recreation:
- `allow-iap-ssh` firewall.
- Existing Router and NAT.
- OS Login / OS Admin IAM.
- API services (`compute`, `oslogin`).

## Available outputs
This stack publishes outputs so other stacks (for example `packer-dev`) can reuse global networking without hardcoded values:
- `project_id`
- `region`
- `network_name`
- `network_self_link`
- `iap_ssh_firewall_name`
- `iap_ssh_firewall_self_link`
- `cloud_router_name`
- `cloud_nat_name`
- `cloud_nat_self_link`

## Policy as Code (OPA/Conftest)

- Policy directory: `environments/global/policy-global`
- Static policies on `.tf`:
  - SSH firewall access allowed only from IAP `35.235.240.0/20`
  - Mandatory `target_tags` with `iap-ssh` on the SSH firewall rule
  - Cloud NAT with `log_config.enable = true`
  - Cloud NAT with `enable_endpoint_independent_mapping = true`
  - Required APIs:
    - `compute.googleapis.com`
    - `oslogin.googleapis.com`
- Policies on `tfplan.json`:
  - Block `delete/replace` on shared global resources:
    - `google_compute_firewall`
    - `google_compute_router`
    - `google_compute_router_nat`
  - Runtime revalidation of the IAP SSH rule
  - Runtime revalidation of secure Cloud NAT settings

Responsibility split:
- `security.rego`: static/local validation of Terraform source code.
- `plan-security.rego`: runtime validation of the resolved plan before apply.

## CI/CD Authentication for Global

- The `apply-global` workflow uses a dedicated Service Account created in the `bootstrap-476212` project.
- This Service Account is impersonated from GitHub Actions through `OIDC / Workload Identity Federation (WIF)`.
- The account is intended for the `global` scope of target projects, without reusing the same Terraform state across different projects.
- The active Service Account for this flow is a dedicated global SA, for example `terraform-global-runner-v2@<bootstrap-project>.iam.gserviceaccount.com`.
- The `github-provider` WIF provider uses `google.subject = assertion.repository_id` to avoid depending on GitHub's `sub`, which changes when the workflow uses GitHub Environments.
- The stable subject expected for this repository is the numeric GitHub `repository_id`, so the Service Account must allow a principal with this shape:
  - `principal://iam.googleapis.com/projects/<bootstrap-project-number>/locations/global/workloadIdentityPools/<pool-id>/subject/<repository-id>`

Required roles in `gcloud-live-staging` for this stack:
- `roles/compute.admin`
- `roles/serviceusage.serviceUsageAdmin`
- `roles/resourcemanager.projectIamAdmin`

These roles cover the current `global` environment scope:
- project API enablement and management
- project IAM bindings for OS Login / OS Admin / IAP
- IAP SSH firewall
- Cloud Router
- Cloud NAT

Required permissions in `bootstrap-476212` for the remote state:
- On the Service Account itself:
  - `roles/iam.workloadIdentityUser` for the stable repository principal.
  - `roles/iam.serviceAccountTokenCreator` for the stable repository principal.
  - `roles/iam.serviceAccountTokenCreator` for the Service Account itself.
- On the remote state bucket, for example `gs://<bootstrap-tfstate-bucket>`:
  - `roles/storage.objectAdmin` conditioned to the `live/staging/global/` prefix.
  - `roles/storage.legacyBucketReader` on the bucket to allow the listing required by Terraform's GCS backend.

WIF adjustment context:
- The previous provider used `google.subject = assertion.sub`.
- With `environment: Global`, GitHub emitted a subject such as `repo:<owner>/<repo>:environment:Global`.
- That subject caused `iam.serviceAccounts.getAccessToken denied` errors when impersonating the Service Account.
- Switching to `google.subject = assertion.repository_id` stabilizes the federated identity and decouples impersonation from the Environment name.

## How it is applied
This stack was **applied from the console/terminal** because these are “one-off” resources (created once and managed here).  
Workflows can also be used to maintain consistency and traceability.
