# Entorno `dev`

Este README documenta **todo lo que vive en `environments/dev/`** y cómo se opera en CI/CD.

## Índice

- [Bloque 1: Terraform](#bloque-1-terraform)
- [Bloque 2: Ansible](#bloque-2-ansible)
- [Bloque 3: Workflows que usan esta ruta](#bloque-3-workflows-que-usan-esta-ruta)

## Bloque 1: Terraform

### Rutas

- `environments/dev/main.tf`
- `environments/dev/variables.tf`
- `environments/dev/providers.tf`
- `environments/dev/versions.tf`
- `environments/dev/backend.tf`
- `environments/dev/terraform.tfvars`
- `environments/dev/.tflint.hcl`

### Qué despliega

- Una VM Ubuntu 22.04 en GCP (`google_compute_instance.ubuntu`).
- Tipo de máquina configurable mediante `machine_type` (por defecto `e2-standard-2`).
- Disco de arranque configurable (`disk_size_gb`, tipo `pd-balanced`).
- Etiquetas (`labels`) con `env = dev`.
- Tag de red `iap-ssh` para acceso por IAP.
- IP pública opcional con `create_public_ip`.

### Outputs principales

- `vm_name`
- `vm_zone`
- `vm_internal_ip`

### Optimización y hardening aplicados

- Backend remoto en GCS (`backend.tf`) para estado centralizado.
- Versionado de Terraform/Providers (en `versions.tf`).
- Lint con TFLint (`.tflint.hcl`) dentro del pipeline.
- Cache de plugins Terraform por lockfile del entorno para acelerar `init`.
- Export dinámico de `vm_zone` tras `apply` para encadenar automatizaciones.

### Policy as Code (OPA/Conftest)

- Carpeta de políticas: `environments/dev/policy/terraform-policy`.
- Políticas estáticas sobre `.tf`:
  - `security.rego` (SA por defecto, secure boot, reglas de firewall SSH abierto).
  - `labels.rego` (labels obligatorias y `env=dev`).
- Políticas sobre plan resuelto (`tfplan.json`):
  - `plan-security.rego` (validación runtime sobre `resource_changes`).
- `finops.rego` queda orientado a checks basados en plan (no en valores no resueltos del código fuente).

### Policy as Code (Checkov custom)

- Carpeta de checks custom: `environments/dev/checkov/terraform`.
- Integración en pipeline (`security_checks`):
  - `bridgecrewio/checkov-action@v12`
  - `external_checks_dirs: ${{ needs.changes.outputs.dir }}/checkov/terraform`
- Checks custom actuales:
  - `check_vm_no_default_sa.py`: falla si la VM usa SA `default` o no define SA.
  - `check_vm_secure_boot.py`: exige `shielded_instance_config.enable_secure_boot = true`.
  - `check_firewall_no_ssh_open.py`: bloquea firewall ingress SSH (`22`) desde `0.0.0.0/0`.
- Validación local de sintaxis (opcional):
  - `python3 -m py_compile environments/dev/checkov/terraform/*.py`

## Bloque 2: Ansible

### Rutas

- `environments/dev/ansible/site.yml`
- `environments/dev/ansible/trivy-image-scan.yml`
- `environments/dev/ansible/requirements.yml`
- `environments/dev/ansible/files/**`
- `environments/dev/ansible/templates/**`
- `environments/dev/ansible/web/**`

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
- Imágenes del stack fijadas con tag explícito + digest para mejorar reproducibilidad y trazabilidad.

### Optimización aplicada

- `gather_facts: true` para que `ansible_facts` funcione de forma explícita.
- `pull_policy: if_not_present` en servicios de compose para reducir pulls innecesarios.
- Límites de recursos en servicios clave (p. ej. Prometheus/Grafana).
- Logs rotados por contenedor (`max-size`, `max-file`).
- Escaneo de imágenes con Trivy en modo informativo/no bloqueante para conservar visibilidad sin frenar despliegues cuando todavía no existe parche oficial upstream.

### Escaneo de imágenes con Trivy

- `site.yml` genera reportes de imágenes durante el despliegue normal.
- `trivy-image-scan.yml` permite ejecutar únicamente el escaneo de imágenes, sin redeplegar el stack.
- Los reportes se descargan en `ansible-runtime/trivy-reports/YYYY-MM-DD/`.
- El workflow publica un artifact único con la carpeta completa de reportes fechados para facilitar revisión y trazabilidad.

### Runtime (on-the-fly)

El workflow no depende de inventario persistente. Genera temporalmente en `ansible-runtime/`:

- `hosts.ini`
- `ansible.cfg`
- `hosts_with_zones.list`
- clave SSH efímera

### Archivo de mantenimiento

El archivo `system-maintenance.yml` es usado para la actualizacion de paquetes en distribuciones `Linux`, 
y en mantenimiento de archivos criticos o vulnerabilidades.

Dicho archivo es activado por el workflow `Asnsible-System-Maintenance.yaml` el cual genera todo lo necesario de manera automatica y en `Runtime`.

## Bloque 3: Workflows que usan esta ruta

### 1) `.github/workflows/Apply-Live.yaml` (`name: terraform-apply`)

- Trigger principal: `push` en rama `main` con cambios en `environments/dev/**`.
- También soporta `workflow_dispatch` (restringido a `dev`).
- Flujo: `changes -> security_checks -> plan -> approve_gate -> apply -> publish-env-artifact`.
- `security_checks` ejecuta controles estáticos del entorno:
  - `tflint`
  - `checkov`
  - `trivy config`
  - `trivy fs`
- En `plan` se genera `tfplan.json` y se ejecuta `conftest` contra `policy/terraform-policy`.
- Publica artifacts:
  - `tfplan` (`tfplan.bin`, `tfplan.txt`, `tfplan.json`)
  - `terraform-outputs-dev` (`outputs.json`)
  - `applied-vm-zone` (`vm_zone.txt`)
  - `applied-env` (`env.txt`)

### 2) `.github/workflows/Ansible-Inventory.yaml` (`name: Ansible-Inventory`)

- Trigger:
  - `workflow_dispatch`
  - `workflow_run` desde `terraform-apply` (si concluye en `success`)
- Resuelve entorno desde `env.txt` o input manual.
- Arranca VMs del entorno si estaban paradas (por label `env`).
- Genera inventario runtime y ejecuta:
  - `ansible-playbook -i ansible-runtime/hosts.ini environments/dev/ansible/site.yml`
- En ejecución manual soporta `run_mode`:
  - `deploy`: despliegue Ansible normal.
  - `trivy_scan`: solo escaneo de imágenes con `trivy-image-scan.yml`, sin volver a aplicar la configuración completa.

### Optimización aplicada en workflow Ansible

- `debug_mode` por input para activar solo los pasos de diagnóstico cuando se necesite.
- Checkout dinámico de la rama origen (`head_branch` en `workflow_run`).
- Warm-up SSH por IAP con reintentos/backoff para reducir fallos intermitentes.
- Cache de colecciones/pip con clave basada en dependencias reales.
- Artifact de reportes Trivy con carpeta fechada `YYYY-MM-DD` para conservar varios resultados de forma ordenada.

## Flujo recomendado de operación

1. Cambiar Terraform o Ansible dentro de `environments/dev/**`.
2. Validar localmente políticas estáticas (opcional recomendado):
   - `conftest test environments/dev/*.tf -p environments/dev/policy/terraform-policy`
3. Push a rama `main`.
4. Ejecutar/aprobar `terraform-apply`.
5. Ejecutar (o encadenar) `Ansible-Inventory`.
6. Revisar artifacts y validación final de servicios.
