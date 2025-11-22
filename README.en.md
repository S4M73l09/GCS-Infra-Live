# GCS-Infra-Live EN -> [ES](README.md)

## Infra Apply + Ansible (post-apply) on main branch

This document summarizes the changes made on `main` to safely run Ansible configurations after `terraform apply`, using `OS Login + IAP` (no SSH keys and no public port 22) and an inventory generated *on-the-fly*.

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
ansible/
  site.yml
  requirements.yml
  web/
    index.html
    style.css
  files/
    monitoring/
      docker/
        docker-compose.yml            # (already in place)
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
- `/opt/monitoring`
  - `docker-compose.yml` (Prometheus, Alertmanager, Grafana, Blackbox, node-exporter, web)
  - `prometheus/`
    - `prometheus.yml`
    - `rules/alerts.yml`
  - `alertmanager/`
    - `alertmanager.yml`
  - `grafana/`
    - provisioning, datasources, dashboards, etc.
- `/opt/web01`
  - `index.html`
  - `styles.css`
  - (cualquier otro estático de la página)
```  


## Deployed stack

* `prometheus`

* `alertmanager`

* `node-exporter`

* `web(simple hosting)`

* `grafana` (with Prometheus datasource preconfigured)

* Basic alert rules + host health

* Alerts sent by email via Alertmanager

## Ansible site.yml

The playbook in charge of:

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

Path: `ansible/files/monitoring/docker/docker-compose.yml`.

* `prometheus`-> Collect metrics

* `alertmanager` -> manage alerts

* `node-exporter` -> system metrics (CPU, RAM, Disk, Network)

* `grafana` -> visulization of metrics

* `web (Nginx)` -> the static website works from `opt/web01`

* `blackbox` -> check the HTTP availability of the website

## Docker Networks

* `monitoring` -> Prometheus, Grafana, Alertmanager, node-exporter, blackbox.  

* `web-01` -> Nginx (`web`) + blackbox (to be able to probe `http://web:80`).

The `web` service mounts:

```yaml
volumes:
  - /opt/web01:/usr/share/nginx/html:ro
  ```


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

The Ansible step in the workflow passes these secrets to the playbook as `-e` variables, which the template then uses to generate `alertmanager.yml` on the VM.

## Ecstatic web

* Nginx serves a simple portfolio page/project explanation:
  * Infrastructure description (Terraform + GCP + Github Actions + Ansible + Docker)
  * Youtube video embeds showing the Bootstrap/repo-Live of the infrastructure
  * Links to the Bootstrap and Infra-Live repositories
* HTML/CSS content lives in the repo under `ansible/web` and is copied to `/opt/web01` using Ansible.

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

## Artifacts and visibility

* Inventory and cfg are stored as an artifact:
`ansible-inventory-env` → `ansible/hosts.ini`, `ansible/ansible.cfg`

* You can download it from the **Actions** tab of the corresponding run.

## Best practices we follow

* No SSH keys or public port 22: access via OS Login + IAP.

* Ephemeral (on-the-fly) inventory and no IPs (only GCE FQDNs).

* Workflow concurrency to avoid overlaps.

* Separate jobs for maximum visibility (generate → publish → apply).

