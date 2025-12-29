# GCS-Infra-Live EN -> [ES](README.md)

<!-- toc -->

- [Infra using and baking Packer image](#infra-using-and-baking-packer-image)
- [Infra Apply + Ansible (post-apply) on main branch](#infra-apply--ansible-post-apply-on-main-branch)
  - [Health status of the environment](#-health-status-of-the-environment)
  - [What was added](#what-was-added)
  - [Requirements](#requirements)
  - [Recommended repository structure (In progress)](#recommended-repository-structure-in-progress)
  - [How the full pipeline works](#how-the-full-pipeline-works)
  - [Folder structure in the VM](#folder-structure-in-the-vm)
  - [Deployed stack](#deployed-stack)
  - [Ansible site.yml](#ansible-siteyml)
  - [Docker stack: docker-compose.yml](#docker-stack-docker-compose-yml)
  - [Secure VM Access without Public IP (IAP + VS Code Remote-SSH)](#secure-vm-access-without-public-ip-iap--vs-code-remote-ssh)
  - [Artifacts and visibility](#artifacts-and-visibility)
  - [Best practices we follow](#best-practices-we-follow)

<!-- tocstop -->

## Infra using and baking Packer image

This part describes the structure and creation of resources using a Packer template and Terraform files generated when a `pull_request` from the test branch is opened against `main`. Packer validation already runs in the test branch `feat/dev`.

## Infra Apply + Ansible (post-apply) on main branch

This document summarizes the changes made on `main` to safely run Ansible configurations after `terraform apply`, using `OS Login + IAP` (no SSH keys and no public port 22) and an inventory generated *on-the-fly*.

## 🔍 Health status of the environment

[![Health report](https://github.com/S4M73l09/GCS-Infra-Live/actions/workflows/health-report.yml/badge.svg)](https://github.com/S4M73l09/GCS-Infra-Live/actions/workflows/health-report.yml)

This line is an example of using Python to create an alert system and reports that are saved in the Github artifacts.


## What was added

### 1) Chained workflow: Inventory-And-Ansible.yaml

* Location: `.github/workflows/Inventory-And-Ansible.yaml`
* It is triggered automatically when the `terraform-apply` workflow finishes successfully.
* It runs 3 separate jobs (that “pro” visibility in Actions):

#### *1) generate_inventory*
* Authenticates to GCP via OIDC.
* Generates `ansible/hosts.ini` with RUNNING VMs that have `labels.env=environment (dev by default)`.
* Creates `ansible/ansible.cfg` pointing to `~/.ssh/config (gcloud + IAP)`.
* Verifies that the inventory does not contain IPs (only GCE FQDNs).
* Uploads both files as artifact: `ansible-inventory-env`.

#### *2) publish_inventory*
* Publishes/echoes the ready artifact (optional, for visibility only).

#### *3) run_ansible*
* Downloads the artifact into `ansible/.`
* Installs Ansible.
* Runs `ansible-playbook ansible/site.yml` using `ANSIBLE_CONFIG=ansible/ansible.cfg`.

> 💡 If we want to cover prod, we add `prod` to the `matrix.env` in all three jobs.

---

### 2) Minimal Ansible playbook: ansible/site.yml

* Creates the folder structure on the VM under `/opt/monitoring`.
* Copies (if they exist in the repo) the `Prometheus, Alertmanager, Grafana and Docker` files into the VM.

---

## Requirements

### Repository variables (Settings → Variables)

* `GCP_WORKLOAD_IDENTITY_PROVIDER` (WIF)
* `GCP_SERVICE_ACCOUNT` (SA used by OIDC)

### Required IAM roles for the identity that runs the workflows

* `roles/compute.osAdminLogin` (or `roles/compute.osLogin` if sudo is not needed)
* `roles/iap.tunnelResourceAccessor`

### Network/Firewall

* SSH only through `IAP`.
* OS Login enabled (at project and/or VM level): `enable-oslogin = TRUE`.

### Labels

* VMs that should be included in the inventory must have `labels.env=dev` (or whatever environment you use).

## Recommended repository structure (In progress)

```bash
environments/dev                     # (already added to merge main)
ansible/
  site.yml
  requirements.yml
  web/
    index.html
    style.css
  files/
    monitoring/
      prometheus/
        prometheus.yml                # (already in place)
        rules/
          alerts.yml                  # (already in place)
      grafana/
        provisioning/
          datasources/
            datasource.yml            # (already in place)
          dashboards/
            ejemplo.json              # (already in place)
      template/
        monitoring/
          alertmanager.yml.j2         # (Template that will generate Alertmanager.yml)
          docker-compose.yml.j2       # (Template for docker-compose.yml) 
README.md
README.en.md
renovate.json
```

## How the full pipeline works

1) A merge to `main` is done and `terraform-apply` runs (with environment review if applicable).

2) When it finishes successfully, `inventory-and-ansible` is triggered:

   * **Job 1**: generates inventory by labels and uploads an artifact.

   * **Job 2**: marks artifact visibility (optional).

   * **Job 3**: downloads the artifact into ansible/ and invokes ansible-playbook against your hosts.

   * **Job 4**: installs the required Ansible collection community.docker.

3) After the inventory-and-ansible pipeline finishes:

   * Installs Docker and the Docker Compose plugin on the VM.

   * Copies the monitoring stack to /opt/monitoring.

   * Renders the Alertmanager configuration from a template using GitHub Secrets.

   * Brings up (or updates) the stack with docker compose in an idempotent way.

## Folder structure in the VM
```makefile
/opt
├─ monitoring/
│  ├─ docker/                    # compose working dir
│  │  └─ docker-compose.yml      # rendered by Ansible
│  ├─ prometheus/
│  │  ├─ prometheus.yml          # bind: ../prometheus/prometheus.yml -> /etc/prometheus/prometheus.yml
│  │  └─ rules/                  # bind: ../prometheus/rules -> /etc/prometheus/rules
│  ├─ alertmanager/
│  │  └─ alertmanager.yml        # bind: ../alertmanager/alertmanager.yml -> /etc/alertmanager/alertmanager.yml
│  └─ grafana/
│     └─ provisioning/           # bind: ../grafana/provisioning -> /etc/grafana/provisioning
│
├─ web01/                        # bind: /opt/web01 -> /usr/share/nginx/html (web service)
│   ├─ index.html
│   └─ style.css
│
└─ Docker-managed volumes:
    ├─ prometheus-data           # named volume for Prometheus data
    └─ grafana-data              # named volume for Grafana data
```  


## Deployed stack

* `prometheus`

* `alertmanager`

* `node-exporter`

* `web(simple hosting)`

* `grafana` (with Prometheus datasource preconfigured)

* Basic alert rules + host health

1. Install Docker + compose plugin.

2. Create directories
   * `monitoring_base_dir: /opt/monitoring`
   * `web01_base_dir: /opt/web01`

3. Copy:
   * `docker-compose.yml` and files of Prometheus, Alertmanager and Grafana in `/opt/monitoring`.
   *  Content from `files/web/` (HTML/CSS) to `opt/web01`.

4. Lift or update the stack:
```yaml
community.docker.docker_compose_v2:
  project_src: "{{ monitoring_base_dir }}"
  state: present
  remove_orphans: true
```
When the web or stack files change, the `restart monitoring stack` handler is notified to recreate the containers.

## 🐳 Docker stack: docker-compose.yml

Services defined in `docker-compose.yml`

Path: `ansible/templates/monitoring/docker-compose.yml.j2`.

Ansible copies this template to the VM at `{{ monitoring_base_dir }}/docker/docker-compose.yml` and brings up the stack using `community.docker.docker_compose_v2` (`project_src = {{ monitoring_base_dir }}/docker`).


* `prometheus`-> Collect metrics  
* `alertmanager` -> manage alerts  
* `node-exporter` -> system metrics (CPU, RAM, Disk, Network)  
* `grafana` -> visulization of metrics  
* `web (Nginx)` -> the static website works from `opt/web01`  
* `blackbox` -> check the HTTP availability of the website  

It also adds good practices:

**Prometheus**

- Image `prom/prometheus`.
  - Expose `9090`.
  - Mount configuration and rules as read-only volumes.
  - Persist data in `prometheus-data`.
  - Healthcheck HTTP (`/-/healthy`).
  - Resource limits: ~0.5 CPU and 1 GB of RAM.

**Alertmanager**

- Image `prom/alertmanager`.
  - Expose `9093`.
  - Configure as read-only volume from `./alertmanager/alertmanager`.
  - Healthcheck HTTP (`/-/healthy`).

**Node exporter**

- Image `prom/node-exporter`.
  - Expose `9100`.
  - Mount `/proc`, `/sys` and `/` as read-only for read-only metrics collection.
  - Command to use host paths (`--path.rootfs`, etc.).

**grafana**

- Image `grafana/grafana-oss` (to be fixed to stable version).
  - Expose `3000`.
  - Healthcheck HTTP (`/api/`).
  - Admin user/password are injected from GitHub Secrets through Ansible:
    - `GF_SECURITY_ADMIN_USER="{{ lookup('env', 'GRAFANA_ADMIN_USER') | default('admin') }}"`
    - `GF_SECURITY_ADMIN_PASSWORD="{{ lookup('env', 'GRAFANA_ADMIN_PASSWORD') | default('admin') }}"`
  - Disable new user registration (`GF_USERS_ALLOW_SIGN_UP=false`).
  - Persist data in `grafana-data`.
  - Provisioning is mounted from `./grafana/provisioning`.

**Web (Nginx)**

- Image `nginx:alpine`.
  - Expose `gg`.
  - Serve the static portfolio from `/opt/web01` on the VM (mounted **ro**).

**Blackbox**

- Image `prom/blackbox-exporter`.
  - Expose `9115`.
  - Healthcheck HTTP (`/-/healthy`).
  - Connects to both monitoring and web networks to probe the website.

### Networks and volumes

- Networks:
  - `monitoring`: Prometheus, Alertmanager, Node Exporter, Grafana, Blackbox.
  - `web-01`: Nginx (web) and Blackbox.

- Volumes:
  - `prometheus-data`: data for Prometheus.
  - `grafana-data`: data for Grafana.

### Good practices applied to the docker-compose.yml.j2 template

- **Separation of responsibilities**: each service in its own container (Prometheus, Alertmanager, Node Exporter, Grafana, Nginx, Blackbox).    
- **Security**:  
  - Credentials for Grafana are managed via **GitHub Secrets + Ansible + Jinja2 template**, never in the repo.  
  - Volume configuration is mounted as **read-only**.  
- **Resource control**:  
  - CPU and memory limits for Prometheus and Grafana to avoid saturating the VM.  
- **Logging**:  
  - Driver `json-file` with rotation (`max-size: 10m`, `max-file: 3`) to avoid filling the disk.  
- **Observability of the stack**:  
  - Healthchecks HTTP in Prometheus, Alertmanager, Grafana and Blackbox to detect quickly unhealthy states.
- **Lookup('env')**:  
  - Variables are put in the workflow using `Lookup('env')` to inject them without showing them in the selected templates, improving security.  


## 📊 Prometheus: prometheus.yml + rules

Path: `ansible/files/monitoring/prometheus/prometheus.yml`.

Scrapes:

* `prometheus:9090`

* `alertmanager:9093`

* `node-exporter:9100`

Loads rules from `/etc/prometheus/rules/*.yml`.

***Sends alerts to Alertmanager.***

## Alert rules

Path: `ansible/files/monitoring/prometheus/rules/alerts.yml`.

It includes two rule groups:

* `infra_basic`: general status for targets, Prometheus and Alertmanager.

* `host_health`: host health based on node_exporter metrics (CPU, memory, disk, filesystem read-only, etc.).

*  In addition to adding `blackbox` to monitor the website.
    * blackbox interno:
      * Target: `http://web:80`
    * blackbox externo:
      * Target: `https://Domain.com`

Both jobs use `relabel_configs` to send requests to the `blackbox-exporter` in `blackbox:9115`.

## 📈 Grafana: datasource provisioning

Path: `ansible/files/monitoring/grafana/provisioning/datasources/datasource.yml`.

Datasource for Prometheus created automatically when Grafana starts.

Besides, Grafana uses `secrets and variables` to store the Prometheus user and password for greater security.

## 📬 Alertmanager: template with SMTP and GitHub Secrets

Path: `ansible/templates/monitoring/alertmanager.yml.j2`.

Alertmanager is configured from a Jinja2 template.

SMTP credentials are injected from GitHub Secrets in the Ansible workflow:

## Required GitHub Secrets

In Settings → `Secrets and variables` → `Actions`:

* `ALERT_SMTP_SMARTHOST` → e.g. smtp.gmail.com:587

* `ALERT_SMTP_FROM` → sender email

* `ALERT_SMTP_USER` → SMTP user (usually the same email)

* `ALERT_SMTP_PASS` → application-specific password from the email provider

* `ALERT_SMTP_TO` → destination email (if omitted, ALERT_SMTP_FROM is used)

* `GRAFANA_ADMIN_USER` → Grafana username.

* `GRAFANA_ADMIN_PASSWORD` → Grafana admin password.

The Ansible step in the workflow passes these secrets to the playbook as `-e` variables, which the template then uses to generate `alertmanager.yml` on the VM and the Grafana user and password in the `docker-compose.yml` file.


## Ecstatic web

* Nginx serves a simple portfolio page/project explanation:
  * Infrastructure description (Terraform + GCP + Github Actions + Ansible + Docker)
  * Youtube video embeds showing the Bootstrap/repo-Live of the infrastructure
  * Links to the Bootstrap and Infra-Live repositories
* HTML/CSS content lives in the repo under `ansible/web` and is copied to `/opt/web01` using Ansible.

## Artifacts and visibility

In each run of the `Ansible` workflow at the end of everything, a artifact is generated that can be downloaded from which you can connect to the VM using its real name and other ways using `IAP-Tunnel`.

## Secure VM Access without Public IP (IAP + VS Code Remote-SSH)

This VM (`dev-oslogin-ubuntu`, `europe-west1-b`) has **no public IP**.  
Access is done only via:

- **IAP (Identity-Aware Proxy)**
- **SSH** using a `ProxyCommand` that calls `gcloud` in WSL
- **VS Code Remote-SSH**
- **Port forwarding** for Nginx / Prometheus / Grafana

---

## 1. Requirements

### Local (Windows + WSL)

- Windows 10/11 with **OpenSSH Client**.
- **VS Code** + **Remote - SSH** extension.
- **WSL2 Ubuntu** with:
  - Google Cloud SDK (`gcloud`) installed.
  - Project configured:
    ```bash
    gcloud auth login
    gcloud config set project NAME-Project
    ```
  - SSH key created by `gcloud`:
    `/home/Users/.ssh/google_compute_engine`

Copy the key from WSL to Windows:

```bash
mkdir -p /mnt/c/Users/USER/.ssh
cp /home/USER/.ssh/google_compute_engine \
   /mnt/c/Users/USER/.ssh/google_compute_engine
```
### GCP

  - Projet: `Name-Project`
  - VM: `Name-VM`
  - IAP enabled + the local user´s Google account has IAP/SSH permissions.

## 2. SSH Configuration on Windows

files: `C:\Users\USUARIO\.ssh\config`

```sshconfig
Host gcp-dev-iap
    HostName compute.NUMBERFORDRYRUN
    User USERS

    IdentityFile C:/Users/USUARIO/.ssh/google_compute_engine
    IdentitiesOnly yes

    # IAP tunnel using gcloud in WSL
    ProxyCommand wsl /home/USER/google-cloud-sdk/platform/bundledpythonunix/bin/python3 /home/USER/google-cloud-sdk/lib/gcloud.py compute start-iap-tunnel dev-oslogin-ubuntu %p --listen-on-stdin --project=gcloud-live-dev --zone=europe-west1-b --verbosity=warning

    # Local HTTP forwards
    LocalForward 8080 localhost:80      # Nginx / web
    LocalForward 9090 localhost:9090    # Prometheus
    LocalForward 3000 localhost:3000    # Grafana
```
> - HostName compute.NUMBER comes from
>   - gcloud compute ssh NAME-VM --tunnel-through-iap --dry-run.

## 3. Test SSH connection

In powershell
```bash
ssh gcp-dev-iap
```
If it works you should see:
```bash
USERS@compute.NUMBER:~$
```

While this session is open:

- `http://localhost:8080` → Nginx.
- `http://localhost:9090` → Prometheus.
- `http://localhost:3000` → Grafana.

## 4. Using VS Code Remote-SSH

  1. Open VS Code
  2. Ctrl+Shift+P
  3. Type: `Remote-SSH: Connect to Host`
  4. VS Code will install the ***VS Code Server*** on the VM (First time only)
  5. Bottom-left should show: `SSH: gcp-dev-iap`
  6. `Terminal -> New Terminal` -> expected prompt.
  ```bash
  USERS@compute.NUMBER:~$
  ```
 From here:

 - You edit files directly on the VM.
 - You use the remote terminal for `docker`, logs, etc.
 - Services are reachable via `localhost:8080/9090/3000` without exposing the VM to the internet.

## 5. Quick troubleshooting

- If Remote-SSH gets stuck:
  - On the VM:
```bash
  rm -rf ~/.vscode-server
```
The reconnect from VS Code.

- Make suer `curl`/`wget`exist on the VM so VS Code can download the server:
```bash
sudo apt update
sudo apt install -y curl wget
```

This documents the pattern: ***VM with no public IP + IAP + VS Code Remote-SSH + Local tunnels to internal services***.


## Local validation (WSL)

Tools used to validate configuration before deploying:

* Ansible
  * `ansible-playbook site.yml --syntax-check`

* Prometheus
   * `promtool check config files/monitoring/prometheus/prometheus.yml`
   * `promtool check rules files/monitoring/prometheus/rules/alerts.yml`

* Docker-compose
   * `docker-compose config` (since `files/monitoring/docker`)

* YAML linting
   * `yamllint` about `prometheus.yml`and `alerts.yml` to clean spaces and comments

## Terraform Promotion Flow (`feat/dev` → `main`)

In this repo we use branches like this:

- `main` → **LIVE / production** branch.  
- `feat/dev` → **development and testing** branch (Terraform, workflows, README, etc.).  
- Branches like `feat/tf-...` → **temporary promotion branches**, used only to bring Terraform changes from `feat/dev` into `main`.

The idea is:

> In `feat/dev` I can change anything.  
> Only the Terraform changes I explicitly choose are promoted to `main`, through a promotion branch.

---

### Steps to promote Terraform changes to `main`

We assume the `.tf` files live in `environments/dev`.

1. **Work normally in `feat/dev`**

   - Edit Terraform under `environments/dev`.
   - Test, validate, run `terraform plan`, etc.
   - Commit and `git push` to `feat/dev` until the infra is ready.

2. **When the Terraform changes are ready for production**

   Create a clean promotion branch from `main`:

   ```bash
   # 1) Go to main and update
   git checkout main
   git pull origin main

   # 2) Create a promotion branch (example name)
   git checkout -b feat/tf-update-<description>

Pull in only the Terraform folder from feat/dev:
```
git checkout feat/dev -- environments/dev
```

Check what changed:
```bash
git status
```
→ You should only see files under `environments/dev` as modified.

Commit and push the branch:
```bash
git add environments/dev
git commit -m "Update Terraform from feat/dev`
git push origin feat/tf-update-<description>
```

3. **Create the Pull Request to main**

   - Open a PR: `feat/tf-update-<description> → main`.
   - Review the diff: only files under `environments/dev` should appear.
   - Let the workflows run (lint, plan, etc.).
   - If everything is OK → Merge into `main`.

4. **Clean up the promotion branch (optional but recommended)**

Once the PR is merged:

```bash
# Delete the branch locally
git branch -d feat/tf-update-<description>

# Delete the branch on remote (GitHub)
git push origin --delete feat/tf-update-<description>
```

## Why not use `feat/dev → main` directly?

A PR from `feat/dev → main` would include all changes on that branch (README, workflows, experiments, etc.), not just Terraform.

With this flow:

* `feat/dev` remains a workshop branch where you can change anything.
* `main only receives`, via promotion branches (feat/tf-...),
the Terraform changes that are already ready for production.

## Artifacts and visibility

* Inventory and cfg are stored as an artifact:
`ansible-inventory-env` → `ansible/hosts.ini`, `ansible/ansible.cfg`

* You can download it from the **Actions** tab of the corresponding run.

## Best practices we follow

* No SSH keys or public port 22: access via OS Login + IAP.

* Ephemeral (on-the-fly) inventory and no IPs (only GCE FQDNs).

* Workflow concurrency to avoid overlaps.

* Separate jobs for maximum visibility (generate → publish → apply).
