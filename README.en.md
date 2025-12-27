# Test branch (feat/dev) ES -> [EN](README.en.md)

This document records exactly what the feat/dev branch does: plan flow in PR, plan artifact, workflows, minimum Terraform structure, and requirements in GCP/GitHub.

The index shows two types of resources used, which are not related to each other, they are totally independent and the only thing they share is only that they use Terraform and SA and OIDC, especially generated in Bootstrap.

Both Packer and Terraform use their own SA created in the Bootstrap to separate them for security reasons, everything else is completely independent in itself.

---

<!-- toc -->

- [Packer image and workflows](#packer-image-and-workflows)
  - [Packer (Ubuntu 22.04 IAP + k3s image)](#packer-ubuntu-2204-iap--k3s-image)
  - [GitHub Actions workflow (feat-dev-packer-net-plan)](#github-actions-workflow-feat-dev-packer-net-plan)
  - [Terraform network for packer-dev](#terraform-network-for-packer-dev)
  - [Quick k3s notes](#quick-k3s-notes)
- [General infrastructure (Terraform)](#general-infrastructure-terraform)
  - [Goal](#goal)
  - [Minimal structure](#minimal-structure)
  - [Actions Variables (repo → Settings → Actions → Variables)](#actions-variables-repo--settings--actions--variables)
  - [Terraform (subject to change)](#terraform-subject-to-change)
  - [Requirements in GCP](#requirements-in-gcp)
  - [CI/CD for the `feat/dev` branch](#ci-cd-for-the-feat-dev-branch)
  - [✅ TFLint in this repo (Terraform lint)](#tflint-in-this-repo-terraform-lint)
  - [Automating plugin updates (optional)](#automating-plugin-updates-optional)
  - [Workflows](#workflows)
  - [Workflow demo video](#workflow-demo-video)
  - [✅ Current status (feat/dev)](#current-status-feat-dev)

<!-- tocstop -->

---
# Infrastructure and Packer image

<a id="packer-image-and-workflows"></a>
## Packer image and workflows

<a id="packer-ubuntu-2204-iap--k3s-image"></a>
### Packer (Ubuntu 22.04 IAP + k3s image)
- **Packer (Ubuntu 22.04 IAP + k3s image)**  
  - `environments/packer-dev/gcp-ubuntu-2204-iap/packer.pkr.hcl`: temp VM without public IP (`omit_external_ip=true`, `use_internal_ip=true`) with IAP SSH; network/subnet via vars.  
  - Explicit SA `service_account_email`; labels on VM and image (`image_labels`), `image_family` and `image_storage_locations` set to region.  
  - Provisioner installs pinned versions of `curl`, `git`, `ca-certificates`, `jq`, holds them, and cleans APT cache.  
  - Bakes k3s `v1.34.1+k3s1` installed but stopped (`INSTALL_K3S_SKIP_START=true`); base config at `/etc/rancher/k3s/config.yaml` (traefik/servicelb disabled, flannel vxlan, CIDRs 10.42/10.43, kubeconfig 0644, `node-name: k3s-server-1`). Token **not** baked: generated at runtime when starting the server.  
  - IAP connection: uses `iap-ssh` firewall tag and `packer-dev` tag; ephemeral VM without public IP.

<a id="github-actions-workflow-feat-dev-packer-net-plan"></a>
### GitHub Actions workflow (feat-dev-packer-net-plan)
- **GitHub Actions workflow (feat-dev-packer-net-plan)**  
  - Paths: `environments/packer-dev/**`, branch `feat/dev`. Concurrency enabled.  
  - Terraform job (plan only) in `environments/packer-dev/terraform-net`, OIDC with `GCP_SERVICE_ACCOUNT`, no apply.  
  - Packer job (validate only) depends on plan; OIDC with `GCP_PACKER_SERVICE`; passes `PKR_VAR_*` and `PKR_VAR_service_account_email`.  
  - `packer fmt` formats (no `-check`) to avoid style failures; `packer validate` only (no build).

<a id="terraform-network-for-packer-dev"></a>
### Terraform network for packer-dev
- **Terraform network for packer-dev**  
  - `environments/packer-dev/terraform-net`: dedicated VPC, private subnet, Cloud Router + NAT, firewall IAP→SSH via `iap-ssh` tag.  
  - Outputs: names plus `network_self_link`/`subnetwork_self_link` for downstream modules.  
  - Vars for project/region/vpc/subnet/cidr/tag; assumes same project for network and compute.

<a id="quick-k3s-notes"></a>
### Quick k3s notes
- **Quick k3s notes**  
  - k3s is installed and stopped; when starting the server it generates the token at `/var/lib/rancher/k3s/server/token` (or export `K3S_TOKEN` at runtime).  
  - Server/agent start happens at runtime (cloud-init/script). No default ingress/LB (traefik/servicelb disabled).

### 🧱 Minimal structure
```bash
live-infra/
├─ .github/workflows/  
│  └─  plan.yml                     # Plan in PR + workflow_dispatch, uploads tfplan.bin/txt  
   └─  feat-dev-packer-net-plan.yaml # Validate .tf and Packer.
└─ environments/  
   └─ dev/  
      ├─ backend.tf                # GCS backend (bucket + prefix)  
      ├─ versions.tf               # Terraform version + providers  
      ├─ providers.tf              # Providers for Google Cloud
      ├─ variables.tf              # labels, etc.  
      ├─ main.tf                   # example: empty VPC  
      ├─ terraform.tfvars          # project_id = gcloud-live-
      └─ .terraform.lock.hcl       # versioned in Git (important!)
   └─ packer-dev/  
      ├─ terraform-net/            # Network for packer-dev
         ├─ main.tf
         ├─ outputs.tf
         └─ variables.tf
      └─gcp-ubuntu-2204-iap/
        └─ packer.pkr.hcl          # Baked template for k3s using Packer 
```

## ✅ Verification

This entire branch is validation/testing, which allows you to debug and improve the infrastructure. 

All this works thanks to the Bootstrap project which has what is necessary to expand both SA and use Google Cloud's own OIDC.

---

# General infrastructure

<a id="general-infrastructure-terraform"></a>
## General infrastructure (Terraform)

<a id="goal"></a>
### 🎯 Goal  

* Deploy real infrastructure in GCP for the `dev` environment using:  
  * Terraform with remote backend in GCS (`bootstrap-STATE-NAME`, prefix `live/dev`).
  * OIDC authentication (WIF) from GitHub Actions (no JSON keys).
  * Plan in PR (no apply) + manual Apply that downloads the plan from the PR and applies it exactly.
* Optionally keep `main` clean: the apply does **not** require `main` to have the same `.tf` files.

<a id="minimal-structure"></a>
### 🧱 Minimal structure
```bash
live-infra/  
├─ .github/workflows/  
│  └─  plan.yml                     # Plan in PR + workflow_dispatch, uploads tfplan.bin/txt   
   └─  feat-dev-packer-net-plan.yaml # Validate .tf and Packer.
└─ environments/  
   └─ dev/  
      ├─ backend.tf                # GCS backend (bucket + prefix)  
      ├─ versions.tf               # Terraform version + providers  
      ├─ providers.tf              # Providers google/google-beta  
      ├─ variables.tf              # labels, etc.  
      ├─ main.tf                   # example: empty VPC  
      ├─ terraform.tfvars          # project_id = gcloud-live-dev, region, labels  
      └─ .terraform.lock.hcl       # versioned in Git (important!)  
   └─ packer-dev
      ├─ terraform-net/
         ├─ main.tf
         ├─ outputs.tf
         └─ variables.tf
      └─ gcp-ubuntu-2204-iap/
        └─ packer.pkr.hcl
```  
+ > **Note:** The *apply* workflow (**`apply.yml`**) lives in the **`main` branch** and is run manually (*workflow_dispatch*). Even though the file is in `main`, it applies **exactly the plan** generated in the `feat/dev` PR because it **checks out the PR commit** and **downloads the `tfplan.bin` artifact** from that run.

<a id="actions-variables-repo--settings--actions--variables"></a>
### 🔐 Actions Variables (repo → Settings → Actions → Variables)

* GCP_WORKLOAD_IDENTITY_PROVIDER  
  **`projects/project_number/locations/global/workloadIdentityPools/github-pool-2/providers/github-provider`**

* GCP_SERVICE_ACCOUNT  
  **`terraform-bootstrap@bootstrap-PROJECT_NAME.iam.gserviceaccount.com`**

These come from the Bootstrap project. They are not secrets (stored as **Variables**, not **Secrets**).

<a id="terraform-subject-to-change"></a>
### Terraform (subject to change)

***backend.tf***
```hcl
terraform {
  backend "gcs" {
    bucket = "bootstrap-476212-tfstate"
    prefix = "live/dev"
  }
}
```  

***versions.tf***
```hcl
terraform {
  required_version = "~> 1.9.0"
  required_providers {
    google      = { source = "hashicorp/google",      version = "~> 5.42.0" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 5.42.0" }
  }
}
```

***providers.tf***
```hcl
variable "project_id" {}
variable "region"     { default = "europe-west1" }

provider "google" {
  project = var.project_id
  region  = var.region
}
provider "google-beta" {
  project = var.project_id
  region  = var.region
}
```  

***variables.tf***
```hcl
variable "labels" {
  type    = map(string)
  default = { managed_by = "terraform", env = "dev" }
}
```  

***main.tf*** minimal safe example
```hcl
resource "google_compute_network" "vpc_dev" {
  name                    = "vpc-dev"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}
```  

***terraform.tfvars***
```hcl
project_id = "gcloud-live-dev"
region     = "europe-west1"
labels     = { managed_by = "terraform", env = "dev" }
```  

Lockfile: `environments/dev/.terraform.lock.hcl` is versioned for reproducible builds.

Lockfile verified for the following platforms so they can be used with different providers such as:

* Windows  
* Linux  
* MacOS  

We use `terraform init`, which generates the `.terraform.lock.hcl` file. This is vital for the workflow and is generated per environment. To add the necessary providers we run:
```hcl
terraform providers lock   -platform=linux_amd64   -platform=linux_arm64   -platform=darwin_arm64   -platform=darwin_amd64   -platform=windows_amd64
```

***A note:*** Google does not support Windows ARM as of the date this is published. This may change in the future.

<a id="requirements-in-gcp"></a>
### ☁️ Requirements in GCP

* LIVE project: `gcloud-live-dev` with billing enabled.

* Enabled API: ***compute.googleapis.com***

* Bootstrap Service Account with permissions in the LIVE project:
  * `roles/compute.networkAdmin` (for the test VPC).

* State bucket: `PROJECT_NAME-tfstate` with conditional binding by prefix:
  * Condition: **`resource.name.startsWith('projects/_/buckets/state_name_Bootstrap/objects/live/dev/')`**

<a id="ci-cd-for-the-featdev-branch"></a>
### 🔄 CI/CD for the `feat/dev` branch

### 2) Manual Apply from the PR plan (**workflow defined in `main`**)

**File:** `.github/workflows/apply.yml` **(in the `main` branch)**

1. Resolves the **SHA** of the PR commit and locates the **last successful run** of `terraform-plan`.  
2. **Checks out the PR commit** (not `main`).  
3. Downloads the `tfplan.bin/txt` artifacts from that run.  
4. Runs `terraform init` against the same backend and **`terraform apply tfplan.bin`** (exactly the reviewed plan).

- **Environment:** `dev` (configure *Required reviewers* as an approval gate).

**Flow clarification:**  
- The **test branch (`feat/dev`)** contains the Terraform code and the **`plan.yml`** that generates the plan and the artifacts.
- The **`main` branch** contains **`apply.yml`**. When executed manually, it **does not require a merge**: it takes the **plan from the PR** and the **exact code from the PR commit**, allowing you to keep `main` clean.

<a id="tflint-in-this-repo-terraform-lint"></a>
### ✅ TFLint in this repo (Terraform lint)

To improve security and detect Terraform issues early in the different files, a `.tflint` setup was added.

***Purpose:*** detect `Terraform` issues before `plan/apply` (types, deprecated resources, Google provider rules and any other provider rules, etc.)

### What was added:
* Configuration file: `environments/dev/.tflint.hcl`
* Google rules plugin: `tflint-ruleset-google` (***exact version:*** `0.37.1`)
* CI job (plan workflow):
  * `tflint --init` (downloads the plugin)
  * `tflint` (runs the lint)

### Local installation (optional)  
```bash
# (Ubuntu/WSL) install unzip if missing
sudo apt-get update && sudo apt-get install -y unzip

# Install TFLint
curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
tflint --version

# Initialize and run in the dev environment
cd environments/dev
tflint --init
tflint
```  

### Issues that appeared and how they were fixed

1. `apt update` failed (NO_PUBKEY for Google Cloud SDK repo)  
   * Solution: reimport the key and update:
  ```bash
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/google-cloud-sdk.gpg
    echo "deb [signed-by=/etc/apt/keyrings/google-cloud-sdk.gpg] https://packages.cloud.google.com/apt cloud-sdk main"      | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
    sudo apt-get update
  ```  

2. `unzip` was missing (the TFLint installer could not extract the archive)  
   * Solution: `sudo apt-get install -y unzip`  

3. TFLint ↔ Google plugin error due to incompatible API version  
   * Cause: the plugin was too old for the installed TFLint.  
   * Solution: ***pin a recent exact version*** in `.tflint.hcl`:
   ```hcl
    plugin "google" {
      enabled = true
      source  = "github.com/terraform-linters/tflint-ruleset-google"
      version = "0.37.1"   # exact version, no >=
    }
   ```
   * Note: clear cache before re-initializing:
   ```bash
   rm -rf ~/.tflint.d/plugins || true
   tflint --init
   ```

4. 404 when initializing the plugin  
   * Cause: `version = ">= X.Y.Z"` was used (TFLint does not accept ranges when `source` is specified).  
   * Solution: use an exact version (e.g. `0.37.1`).

5. Lint warnings in the code  
   * Variables without type (`project_id`, `region`) → add `type` (and `default` if applicable):  
   ```hcl
   variable "project_id" { type = string }
   variable "region"     {
     type    = string
     default = "europe-west1"
   }
   ```  
   * Unused `labels` variable → use it in resources (`labels = var.labels`) or remove it.

6. `auth@v2` → “must specify exactly one of workload_identity_provider or credentials_json”  
   * The workflow was using repository secrets instead of variables for OIDC and the Terraform SA.  
   * Solution: modify that line in the workflow so it uses the variables `(vars.<variable_OIDC_GCP>)`.

7. Error: ... `unauthorized_client` ... "credential is rejected by the attribute condition"  
   * This error occurred because the provider CEL expression did not match the real claims (repo/branch/PR).  
   * Solution: adjust mappings and condition by repo ID and allowed branches.

   ***Minimum mappings in the provider:***
```ini
  google.subject              = assertion.sub
  attribute.repository_id     = assertion.repository_id
  attribute.ref               = assertion.ref
  # (useful)
  attribute.repository        = assertion.repository
  attribute.workflow          = assertion.workflow
  attribute.actor             = assertion.actor
  attribute.repository_owner  = assertion.repository_owner
```

   ***Final CEL (two repos by ID + main/feat/dev + PRs):***
```cel
attribute.repository_id in ["1089522719","1083637831"] &&
(
  attribute.ref == "refs/heads/main" ||
  attribute.ref == "refs/heads/feat/dev" ||
  matches(string(attribute.ref), "^refs/pull/")
)
```

Note: `matches(string(...))` is used to avoid the `dyn` type error with `startsWith`, since Google does not accept that here.

8. Bindings for the `Live-Infra` repo on the `Bootstrap` SA  
   * This error occurs if the binding for the `Live-Infra` repo is missing on the `Bootstrap` SA.  
   * Solution: add those bindings to the Bootstrap SA pointing to the `Live-Infra` repo:
```ruby
principalSet://iam.googleapis.com/projects/<BOOTSTRAP_PROJECT_NUMBER>/locations/global/workloadIdentityPools/<POOL_ID>/attribute.repository/S4M73l09/GCS-Infra-Live
principalSet://iam.googleapis.com/projects/<BOOTSTRAP_PROJECT_NUMBER>/locations/global/workloadIdentityPools/<POOL_ID>/attribute.repository/S4M73l09/GCS-Bootstrap---Live
```
***Role: Workload Identity User `(roles/iam.workloadIdentityUser)`***

9. `Unsupported Terraform Core version` (runner on 1.6.5 vs `required_version >= 1.8.0`)  
   * This error occurs when the Terraform version does not match the `required_version` in `versions.tf`.  
   * Solution: use `hashicorp/setup-terraform@v3` with `terraform_version: 1.9.7`, `terraform_wrapper: false`.
     * Version check in the job.
     * Provider pins: `google`/`google-beta ~> 5.45`.
     * `terraform init -lockfile=readonly`.

<a id="automating-plugin-updates-optional"></a>
### Automating plugin updates (optional)

A Renovate App was added with `Renovate.json` in `main` to open PRs that update the line:
```hcl
version = "X.Y.Z"
```  
in `tflint.hcl` files.  
Configured to target the `feat/dev` branch in ***Scan and Alert*** mode.

<a id="workflows-1"></a>
### Workflows

1) **`Live-Plan.yaml`** (`feat/dev` branch)

  * Trigger: `pull_request` (changes in **`environments/**`**) and **`workflow_dispatch`**.
  * Does: **`init (lockfile readonly)`** -> **`validate`** -> **`plan`** -> uploads artifacts: **`tfplan.bin`** (appliable) and **`tfplan.txt`** (readable).
  * TFLint with cache (`~/.tflint.d/plugins`), `tflint --init`, “pretty” output and **SARIF** + upload to Code Scanning.
  * Terraform plugin cache (`~/.terraform.d/plugin-cache`) and `terraform.rc`.

  * ***Extras:*** env selector by folder; optional inputs for forced modes:
    * **`force_refresh=true`** -> **`refresh-only`**
    * **`replace_targets="addr1,addr2"`** -> **`-replace`**
    * **`destroy=true`** -> **`-destroy`**
        (Restricted to my user in **`workflow_dispatch`**)
    * **`Infracost`** integrated (plan → comment in PR).

2) **`Live-Apply.yaml`** (Lives in `main`)

  * Trigger: **`workflow_dispatch`** with input **`pr_number`** (and **`env_dir=dev`**).
  * Does: resolves PR SHA -> downloads the artifact from the last successful plan -> **`checkout`** of that exact commit -> **`init`** -> **`apply tfplan.bin`**.
  * Environment: **`dev`** with *Required reviewers* (approval before applying).

<a id="workflow-demo-video"></a>
### Workflow demo video

<video src="https://github.com/user-attachments/assets/27e975c5-c57c-48c8-925e-55249caee128" controls style="max-width: 100%; height: auto;"> Workflow demo video </video>

Image showing complete diagram + artifacts

<p align="center">
  <img
    src="https://github.com/user-attachments/assets/b6f8dc87-ecc9-45f5-b366-da1f3958f867"
    alt="Image that shows the complete diagram + artifacts"
    style="max-width: 100%; height: auto;"
  />
</p>

<a id="current-status-featdev"></a>
### ✅ Current status (feat/dev)

  * `GCS backend` working (`live/dev`) ✔  
  * `OIDC/WIF` configured and tested ✔  
  * Plan in PR with `artifacts` ✔  
  * Manual apply from `main (exact plan)` ✔  
  * `Lockfile` versioned and CI in read-only mode ✔  
  * `tflint.hcl` to improve security ✔  
  * `Infracost_api` added to visualize costs ✔
