# Entorno `staging`

Este README documenta **todo lo que vive en `environments/staging/`** y cómo se opera en CI/CD.

## Índice

- [Bloque 1: Terraform](#bloque-1-terraform)
- [Bloque 2: Ansible](#bloque-2-ansible)
- [Bloque 3: Workflows que usan esta ruta](#bloque-3-workflows-que-usan-esta-ruta)

## Bloque 1: Terraform

### Rutas

- `environments/staging/main.tf`
- `environments/staging/variables.tf`
- `environments/staging/providers.tf`
- `environments/staging/versions.tf`
- `environments/staging/backend.tf`
- `environments/staging/terraform.tfvars`
- `environments/staging/.tflint.hcl`

### Qué despliega

- Una VM Ubuntu 22.04 en GCP (`google_compute_instance.ubuntu`).
- `machine_type` custom calculado por `series + vcpus + memory_mb`.
- Disco de arranque configurable (`disk_size_gb`, tipo `pd-balanced`).
- Etiquetas (`labels`) con `env = staging`.
- Tag de red `iap-ssh` para acceso por IAP.
- IP pública opcional con `create_public_ip`.

### Outputs principales

- `vm_name`
- `vm_zone`
- `vm_internal_ip`
- `vm_external_ip`

### Optimización y hardening aplicados

- Backend remoto en GCS (`backend.tf`) para estado centralizado.
- Versionado de Terraform/Providers (en `versions.tf`).
- Lint con TFLint (`.tflint.hcl`) dentro del pipeline.
- Cache de plugins Terraform por lockfile del entorno para acelerar `init`.
- Export dinámico de `vm_zone` tras `apply` para encadenar automatizaciones.

## Bloque 2: Ansible

### Rutas

- `environments/staging/ansible/site.yml`
- `environments/staging/ansible/requirements.yml`
- `environments/staging/ansible/files/**`
- `environments/staging/ansible/templates/**`
- `environments/staging/ansible/web/**`

### Qué configura

- Instalación de Docker + Compose plugin en la VM.
- Despliegue de stack de observabilidad y web:
  - Prometheus
  - Alertmanager
  - Node Exporter
  - Grafana
  - Blackbox Exporter
  - Nginx
- Provisioning de ficheros de Prometheus/Grafana y plantillas de compose/alertmanager.

### Optimización aplicada

- `gather_facts: true` para que `ansible_facts` funcione de forma explícita.
- `pull_policy: if_not_present` en servicios de compose para reducir pulls innecesarios.
- Límites de recursos en servicios clave (p. ej. Prometheus/Grafana).
- Logs rotados por contenedor (`max-size`, `max-file`).

### Runtime (on-the-fly)

El workflow no depende de inventario persistente. Genera temporalmente en `ansible-runtime/`:

- `hosts.ini`
- `ansible.cfg`
- `hosts_with_zones.list`
- clave SSH efímera

## Bloque 3: Workflows que usan esta ruta

### 1) `.github/workflows/Apply-Live.yaml` (`name: terraform-apply`)

- Trigger principal: `push` en rama `staging` con cambios en `environments/staging/**`.
- También soporta `workflow_dispatch` (restringido a `staging`).
- Flujo: `changes -> plan -> approve_gate -> apply -> publish-env-artifact`.
- Publica artifacts:
  - `tfplan` (`tfplan.bin`, `tfplan.txt`, `tfplan.json`)
  - `terraform-outputs-staging` (`outputs.json`)
  - `applied-vm-zone` (`vm_zone.txt`)
  - `applied-env` (`env.txt`)

### 2) `.github/workflows/Ansible-Inventory.yaml` (`name: Ansible-Inventory`)

- Trigger:
  - `workflow_dispatch`
  - `workflow_run` desde `terraform-apply` (si concluye en `success`)
- Resuelve entorno desde `env.txt` o input manual.
- Arranca VMs del entorno si estaban paradas (por label `env`).
- Genera inventario runtime y ejecuta:
  - `ansible-playbook -i ansible-runtime/hosts.ini environments/staging/ansible/site.yml`

### Optimización aplicada en workflow Ansible

- `debug_mode` por input para activar solo los pasos de diagnóstico cuando se necesite.
- Checkout dinámico de la rama origen (`head_branch` en `workflow_run`).
- Warm-up SSH por IAP con reintentos/backoff para reducir fallos intermitentes.
- Cache de colecciones/pip con clave basada en dependencias reales.

## Flujo recomendado de operación

1. Cambiar Terraform o Ansible dentro de `environments/staging/**`.
2. Push a rama `staging`.
3. Ejecutar/aprobar `terraform-apply`.
4. Ejecutar (o encadenar) `Ansible-Inventory`.
5. Revisar artifacts y validación final de servicios.
