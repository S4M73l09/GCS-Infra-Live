# terraform-net (packer-dev)

Stack de Terraform para el entorno `packer-dev` en `staging`.

## Qué despliega

- VPC dedicada (`auto_create_subnetworks = false`)
- Subred privada
- Cloud Router + Cloud NAT
- Firewall de SSH solo vía IAP
- VM sin IP pública basada en imagen de Packer

## Cambios añadidos recientemente

- Alineación de nombres/labels para `staging` (`-stg`, `env=staging`).
- Ajuste FinOps de `vm_machine_type` por defecto a `e2-small`.
- Backend remoto GCS para estado compartido.
- Versionado de providers con lockfile (`.terraform.lock.hcl`).
- `required_providers` actualizados con:
  - `hashicorp/google ~> 7.21`
  - `hashicorp/archive ~> 2.5`

## Módulos

- Carpeta: `modules/`
- Módulo actual: `auto-stop-idle`
  - Detecta inactividad (alert policy de Monitoring)
  - Publica evento en Pub/Sub
  - Ejecuta apagado de VM con Cloud Function 2nd gen
  - IAM mínimo para la SA de auto-stop

## Estructura principal

- `main.tf`: recursos de red + VM + llamada al módulo
- `variables.tf`: variables de entrada del stack
- `providers.tf`: configuración de provider `google`
- `versions.tf`: versiones requeridas de Terraform/providers
- `backend.tf`: backend remoto GCS
- `outputs.tf`: salidas del stack
- `modules/auto-stop-idle/`: lógica de autoapagado por inactividad

## Dependencias de la función (módulo auto-stop-idle)

Se usa estrategia de lock de dependencias:

- `function/requirements.in`: intención (rango controlado)
- `function/requirements.txt`: lock generado (versiones exactas)

Comando para regenerar lock:

```bash
python3 -m piptools compile requirements.in -o requirements.txt
```

## Flujo recomendado

1. `terraform init -upgrade`
2. `terraform fmt -recursive`
3. `terraform validate`
4. `terraform plan`

