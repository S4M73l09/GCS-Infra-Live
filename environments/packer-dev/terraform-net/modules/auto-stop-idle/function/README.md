# Function (auto-stop-idle)

Implementación de la Cloud Function 2nd gen usada por el módulo `auto-stop-idle`.

## Objetivo

Recibir eventos de Pub/Sub (emitidos por la política de inactividad) y ejecutar el apagado de la VM objetivo con la API de Compute Engine.

## Archivos

- `main.py`: lógica de parada (`compute.instances.stop`).
- `requirements.in`: dependencias directas con rango controlado.
- `requirements.txt`: lock de dependencias generado con `pip-compile`.

## Variables de entorno esperadas

Se inyectan desde Terraform (`function.tf`):

- `PROJECT_ID`
- `ZONE`
- `INSTANCE_NAME`

## Dependencias

Dependencia principal:

- `google-api-python-client`

Estrategia recomendada:

- Mantener `requirements.in` como fuente editable.
- Regenerar `requirements.txt` lockeado para despliegues reproducibles.

## Regenerar lock de dependencias

```bash
cd environments/packer-dev/terraform-net/modules/auto-stop-idle/function
python3 -m piptools compile requirements.in -o requirements.txt
```

## Validación rápida local

```bash
python3 -m py_compile main.py
```

## Notas operativas

- Esta función se despliega como Cloud Function 2nd gen desde Terraform.
- Los permisos de apagado los aporta la Service Account definida en `iam.tf`.
- Antes de pasar a `main/prod`, revisar lock de dependencias y umbrales de inactividad del módulo.
