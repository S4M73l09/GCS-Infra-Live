# Módulo auto-stop-idle

Módulo de Terraform para reducir coste en `packer-dev` apagando automáticamente una VM cuando se detecta inactividad sostenida.

## Qué implementa actualmente

- Topic de Pub/Sub para eventos de autoapagado.
- Canal de notificación de Cloud Monitoring hacia Pub/Sub.
- Alert Policy de inactividad por CPU para una VM específica.
- Service Account dedicada para ejecutar el apagado.
- IAM mínimo para operación de apagado y logging.
- Cloud Function 2nd gen disparada por Pub/Sub.
- Código Python que ejecuta `compute.instances.stop`.

## Recursos del módulo

- `google_pubsub_topic.idle_stop`
- `google_monitoring_notification_channel.idle_pubsub`
- `google_monitoring_alert_policy.vm_idle_cpu`
- `google_service_account.auto_stop_sa`
- `google_project_iam_member.auto_stop_compute`
- `google_project_iam_member.auto_stop_logging`
- `google_storage_bucket.function_src`
- `data.archive_file.function_zip`
- `google_storage_bucket_object.function_zip`
- `google_cloudfunctions2_function.auto_stop`

## Variables de entrada

- `project_id`: proyecto GCP.
- `region`: región para Cloud Function/event trigger.
- `zone`: zona de la VM objetivo.
- `instance_name`: nombre de la VM objetivo.
- `instance_id`: instance_id de la VM (usado para filtrar métricas de Monitoring).
- `enable_idle_policy`: habilita/deshabilita los recursos de política idle.
- `idle_cpu_threshold`: umbral de CPU (ej. `0.03`).
- `idle_duration_seconds`: duración mínima de inactividad (ej. `7200`).

## Salidas

- `target`: referencia lógica `project/zone/instance_name`.
- `idle_stop_topic`: id del topic Pub/Sub (o `null` si está deshabilitado).

## Estructura interna

- `main.tf`: Pub/Sub + Monitoring.
- `iam.tf`: Service Account y roles.
- `function.tf`: empaquetado y despliegue de Cloud Function 2nd gen.
- `variables.tf`: entradas.
- `outputs.tf`: salidas.
- `function/main.py`: lógica de apagado.
- `function/requirements.in`: intención de dependencias.
- `function/requirements.txt`: lock de dependencias generado con `pip-compile`.

## Dependencias Python (Function)

Estrategia usada:

- `requirements.in` para declarar dependencia directa con rango controlado.
- `requirements.txt` lockeado para despliegues reproducibles.

Regeneración de lock:

```bash
cd environments/packer-dev/terraform-net/modules/auto-stop-idle/function
python3 -m piptools compile requirements.in -o requirements.txt
```

## Integración en el stack raíz

Se consume desde:

- `environments/packer-dev/terraform-net/main.tf`

Con bloque `module "auto_stop_idle"` pasando:

- `project_id`
- `region`
- `zone`
- `instance_name`
- `instance_id`

## Validación recomendada

```bash
cd environments/packer-dev/terraform-net
terraform init -upgrade
terraform fmt -recursive
terraform validate
terraform plan
```

## Notas operativas

- El módulo está orientado a `staging` como entorno de validación.
- Antes de promover a `main/prod`, ajustar umbrales y ventanas para evitar apagados no deseados.
- Revisar periódicamente IAM y dependencias lockeadas.
