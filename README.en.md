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

## Deployed stack

* `prometheus`

* `alertmanager`

* `node-exporter`

* `grafana` (with Prometheus datasource preconfigured)

* Basic alert rules + host health

* Alerts sent by email via Alertmanager

## 🐳 Docker stack: docker-compose.yml

Services defined in `docker-compose.yml`

Path: `ansible/files/monitoring/docker/docker-compose.yml`.

* prometheus

* alertmanager

* node-exporter

* grafana

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

## Artifacts and visibility

* Inventory and cfg are stored as an artifact:
`ansible-inventory-env` → `ansible/hosts.ini`, `ansible/ansible.cfg`

* You can download it from the **Actions** tab of the corresponding run.

## Best practices we follow

* No SSH keys or public port 22: access via OS Login + IAP.

* Ephemeral (on-the-fly) inventory and no IPs (only GCE FQDNs).

* Workflow concurrency to avoid overlaps.

* Separate jobs for maximum visibility (generate → publish → apply).

