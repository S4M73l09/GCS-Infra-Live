# Infra Live - Índice de Entornos

Este README funciona como punto de entrada por entorno en la rama `main`.

## Índice

- [Entorno Dev](#entorno-dev)
- [Entorno Global](#entorno-global)

---

## Entorno Dev

<details open>
<summary><strong>Ver detalle completo de Dev</strong></summary>

### Alcance

- Terraform: `environments/dev`
- Ansible: `environments/dev/ansible`
- Workflows principales:
  - `.github/workflows/Apply-Live.yaml` (`name: terraform-apply`)
  - `.github/workflows/Ansible-Inventory.yaml` (`name: Ansible-Inventory`)

### Estructura

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

Qué crea:

- VM Ubuntu 22.04 (`google_compute_instance`)
- Labels de entorno (`env = dev`)
- Outputs:
  - `vm_name`
  - `vm_zone`
  - `vm_internal_ip`
  - `vm_external_ip`

Parámetros clave (`terraform.tfvars`):

- `project_id`, `region`, `zone`
- `series`, `vcpus`, `memory_mb`
- `disk_size_gb`
- `create_public_ip`

### Ansible (`environments/dev/ansible`)

Qué aplica:

- Bootstrap/configuración de host
- Stack de monitoring/web por template compose
- Prometheus, Alertmanager, Grafana, Nginx y Blackbox

Rutas importantes:

- Playbook: `environments/dev/ansible/site.yml`
- Compose template: `environments/dev/ansible/templates/monitoring/docker-compose.yml.j2`
- Prometheus: `environments/dev/ansible/files/monitoring/prometheus/prometheus.yml`
- Alertas: `environments/dev/ansible/files/monitoring/prometheus/rules/alerts.yml`

### Workflows de Dev

#### `Apply-Live.yaml` (`terraform-apply`)

- Trigger principal: `push` a `main` con cambios en `environments/dev/**`
- `workflow_dispatch` restringido a `dev`
- Flujo: detecta entorno -> plan -> aprobación por environment -> apply
- Incluye:
  - cache Terraform/TFLint
  - `tflint --init` + lint
  - export de `outputs.json`
  - artifacts `applied-env` y `applied-vm-zone`

#### `Ansible-Inventory.yaml` (`Ansible-Inventory`)

- Trigger:
  - `workflow_dispatch`
  - `workflow_run` desde `terraform-apply` (main)
- Genera inventario runtime en `ansible-runtime/`
- Warm-up SSH por IAP con reintentos/backoff
- Ejecuta `environments/dev/ansible/site.yml`

### Optimizaciones aplicadas

- Runtime efímero en `ansible-runtime/`
- `debug_mode` bajo demanda
- Warm-up SSH por IAP con retries/backoff
- Cache de Terraform/TFLint/Ansible
- `pull_policy: if_not_present` en servicios docker

### Flujo recomendado

1. Editar en `environments/dev/**` o `environments/dev/ansible/**`
2. Push a `main`
3. Ejecutar `terraform-apply`
4. Ejecutar/encadenar `Ansible-Inventory`
5. Validar artefactos y estado final

Documentación específica:

- [README dev](environments/dev/README.md)
- [README dev EN](environments/dev/README.en.md)

</details>

## Entorno Global

<details>
<summary><strong>Ver resumen de Global</strong></summary>

`global` contiene recursos compartidos/base (por ejemplo red base, IAM común y elementos reutilizables).

Ruta:

- `environments/global`

</details>
