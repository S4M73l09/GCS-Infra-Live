# Módulos de Terraform (packer-dev)

Este directorio contiene módulos reutilizables para `environments/packer-dev/terraform-net`.

## Objetivo

Separar funcionalidades avanzadas de los recursos base del stack (`network`, `nat`, `vm`) y permitir evolución incremental sin romper la infraestructura principal.

## Módulo actual: `auto-stop-idle`

Implementa automatización FinOps para reducir coste de runtime:

- Detección de inactividad mediante Cloud Monitoring.
- Emisión de evento a Pub/Sub.
- Ejecución de apagado con Cloud Function 2nd gen.
- Permisos IAM de mínimo privilegio para la SA de auto-stop.

## Archivos relevantes del módulo

- `main.tf`: Pub/Sub + Monitoring Alert Policy
- `iam.tf`: SA y bindings IAM
- `function.tf`: bucket de código, empaquetado zip (`archive_file`) y despliegue de Cloud Function
- `variables.tf`: entradas del módulo
- `outputs.tf`: salidas del módulo
- `function/main.py`: lógica `compute.instances.stop`
- `function/requirements.in` y `function/requirements.txt`: estrategia de dependencias lockeadas

## Integración

El módulo se consume desde:

- `environments/packer-dev/terraform-net/main.tf`

Parámetros clave que recibe:

- `project_id`
- `region`
- `zone`
- `instance_name`
- `instance_id`

## Notas operativas

- Este módulo está orientado a `staging` como entorno de validación.
- Antes de promover a `main/prod`, revisar thresholds, IAM y estrategia de exclusiones para evitar apagados no deseados.
