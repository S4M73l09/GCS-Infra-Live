# Ansible (packer-dev)

Configuración Ansible para el entorno `packer-dev`, ejecutada en CI/CD con inventario generado en runtime.

## Objetivo

Aplicar configuración post-provisioning sobre la VM creada por Terraform/Packer:

- Arranque y bootstrap de k3s.
- Operaciones base sobre Kubernetes.
- Ejecución segura por IAP + OS Login sin versionar `hosts.ini` ni `ansible.cfg`.

## Estructura

- `playbooks/k3s-bootstrap.yml`
  - Arranca y habilita `k3s`.
  - Espera el kubeconfig.
  - Extrae kubeconfig y lo guarda en runner para tareas posteriores.

- `playbooks/k3s-base.yml`
  - Ejemplo base de operación Kubernetes con `kubernetes.core.k8s`.

- `group_vars/all.yml`
  - Variables comunes (`k3s_service_name`, rutas de kubeconfig, etc.).

- `requirements.txt`
  - Dependencias Python para ejecución Ansible en runner.

- `requirements.yml`
  - Colecciones de Ansible a instalar (`kubernetes.core`, `community.general`, `ansible.posix`).

## Ejecución en CI/CD

Workflow asociado:

- `.github/workflows/packer-ansible-runtime.yaml`

Características clave:

- Genera `hosts.ini` y `ansible.cfg` en runtime (`RUNNER_TEMP`).
- Genera clave SSH efímera y la registra en OS Login con TTL.
- Conexión por IAP (sin IP pública, sin inventario persistido en repo).
- Permite `check_mode` vía `workflow_dispatch`.

## Inputs del workflow (manual)

- `playbook`: ruta relativa dentro de `environments/packer-dev/ansible`.
  - Default: `playbooks/k3s-bootstrap.yml`
- `check_mode`: `true/false`.
  - Si es `true`, ejecuta `ansible-playbook --check`.

## Dependencias

Instalación Python (workflow):

- Si existe `requirements.txt`, instala desde ese archivo.
- Si no existe, fallback a `ansible-core`.

Instalación de colecciones:

- Si `requirements.yml` tiene contenido, ejecuta `ansible-galaxy collection install -r requirements.yml`.

## Buenas prácticas aplicadas

- No versionar inventario ni configuración sensible de conexión.
- Uso de credenciales efímeras (SSH key temporal + OS Login TTL).
- Separación de responsabilidades: infra (Terraform/Packer) vs configuración (Ansible).
- Soporte de validación segura con `check_mode`.
