# ¿Que es este proyecto?

Este proyecto se basa en un despliegue de infraestructura totalmente controlado y automatizado en la plataforma en la nube de `Google Cloud platform` asegurando seguridad, escalabilidad, monitorizacion y control por **entornos/ramas**.


# Infra Live - Índice de Entornos

Este README funciona como punto de entrada por entorno en la rama `main`.

## Índice

- [Entorno Dev](#entorno-dev)
- [Entorno Packer-dev](#entorno-packer-dev)

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
  checkov/
    terraform/
  policy/
    terraform-policy/
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

Parámetros clave (`terraform.tfvars`):

- `project_id`, `region`, `zone`
- `machine_type`
- `disk_size_gb`
- `create_public_ip`
- `vm_service_account`

Nota técnica:

- `machine_type` se define directamente por variable, por ejemplo `e2-standard-2`.

### Ansible (`environments/dev/ansible`)

Qué aplica:

- Bootstrap/configuración de host
- Stack de monitoring/web por template compose
- Prometheus, Alertmanager, Grafana y Nginx

Rutas importantes:

- Playbook: `environments/dev/ansible/site.yml`
- Compose template: `environments/dev/ansible/templates/monitoring/docker-compose.yml.j2`
- Prometheus: `environments/dev/ansible/files/monitoring/prometheus/prometheus.yml`
- Alertas: `environments/dev/ansible/files/monitoring/prometheus/rules/alerts.yml`

### Workflows de Dev

#### `Apply-Live.yaml` (`terraform-apply`)

- Trigger principal: `push` a `main` con cambios en `environments/dev/**`
- Flujo: detecta entorno -> plan -> aprobación por environment -> apply
- Incluye:  
  - `Checkov, Trivy, Conftest (OPA)`  
  - cache Terraform/TFLint
  - `tflint --init` + lint
  - export de `outputs.json`
  - artifact `applied-env` para encadenar Ansible

#### `Ansible-Inventory.yaml` (`Ansible-Inventory`)

- Trigger:
  - `workflow_dispatch`
  - `workflow_run` desde `terraform-apply` (dev)
- Genera inventario runtime en `ansible-runtime/`
- Descubre zona dinámica por VM en runtime
- Soporta `debug_mode` para pasos de diagnóstico
- Ejecuta `environments/dev/ansible/site.yml`

### Optimizaciones aplicadas

- Runtime efímero en `ansible-runtime/`
- `debug_mode` bajo demanda
- Warm-up SSH por IAP con retries/backoff
- Cache de Terraform/TFLint/Ansible
- `pull_policy: if_not_present` en servicios docker de dev
- `Security Checks`en workflow `Apply-Live.yaml`

### Flujo recomendado

1. Editar en `environments/dev/**` o `environments/dev/ansible/**`
2. Push a `main`
3. Ejecutar `terraform-apply`
4. Ejecutar/encadenar `Ansible-Inventory`
5. Validar artefactos y estado final

Documentación especifica (Técnica)

- [README dev](environments/dev/README.md)
- [README dev EN](environments/dev/README.en.md)

</details>

---

## Entorno Packer-dev

<details>
<summary><strong>Ver resumen de Packer-dev</strong></summary>

`packer-dev` se usa para el flujo de imagen base + red/VM de laboratorio y automatización asociada.

Ubicaciones:

- Terraform net: `environments/packer-dev/terraform-net`
- Ansible packer: `environments/packer-dev/ansible`
- Plantilla Packer: `environments/packer-dev/gcp-ubuntu-2204-iap`

Documentación específica (detalle técnico):

- [README Terraform net](environments/packer-dev/terraform-net/README.md)
- [README Ansible packer](environments/packer-dev/ansible/README.md)
- [README módulos Terraform](environments/packer-dev/terraform-net/modules/README.md)

</details>

## Rama Dev

`La rama main` sera actualizada periodicamente para mostrar los cambios actuales y antiguos para mejorar la documentacion. Esta rama es para `pruebas`, `validaciones`, `mejoras continuas`, updates de providers, optimizaciones y escalabilidad real manteniendo enfoque `FinOps`.