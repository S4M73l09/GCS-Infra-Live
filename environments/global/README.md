# Global Terraform (recursos de proyecto)

Este stack contiene **recursos globales de proyecto** que se comparten entre entornos (dev/staging). No debe duplicarse por entorno.

## Qué recursos gestiona
- APIs del proyecto: `compute.googleapis.com`, `oslogin.googleapis.com`.
- Metadatos del proyecto (fuera de Terraform):
  - `enable-oslogin`
  - `block-project-ssh-keys`
- IAM OS Login:
  - `roles/compute.osLogin`
  - `roles/compute.osAdminLogin`
- Firewall IAP SSH: `allow-iap-ssh`.
- Cloud Router + Cloud NAT (salida sin IP pública).

## Qué se ha aislado aquí
Estos recursos estaban antes dentro de entornos (dev/staging) y se han aislado para evitar colisiones y duplicados entre estados:
- Metadatos del proyecto (quedan fuera de este stack).
- IAM OS Login/OS Admin.
- Firewall IAP.
- Router + NAT.

## Qué se ha importado
Se importaron recursos ya existentes del proyecto a este estado global para no recrearlos:
- Firewall `allow-iap-ssh`.
- Router y NAT existentes.
- IAM OS Login / OS Admin.
- Servicios de API (`compute`, `oslogin`).

## Outputs disponibles
Este stack publica outputs para que otros stacks (por ejemplo `packer-dev`) reutilicen la red global sin hardcodear:
- `project_id`
- `region`
- `network_name`
- `network_self_link`
- `iap_ssh_firewall_name`
- `iap_ssh_firewall_self_link`
- `cloud_router_name`
- `cloud_nat_name`
- `cloud_nat_self_link`

## Policy as Code (OPA/Conftest)

- Carpeta de políticas: `environments/global/policy-global`
- Políticas estáticas sobre `.tf`:
  - Firewall SSH solo desde IAP `35.235.240.0/20`
  - `target_tags` obligatoria con `iap-ssh` en la regla de firewall SSH
  - Cloud NAT con `log_config.enable = true`
  - Cloud NAT con `enable_endpoint_independent_mapping = true`
  - APIs obligatorias:
    - `compute.googleapis.com`
    - `oslogin.googleapis.com`
- Políticas sobre `tfplan.json`:
  - Bloqueo de `delete/replace` sobre recursos globales compartidos:
    - `google_compute_firewall`
    - `google_compute_router`
    - `google_compute_router_nat`
  - Revalidación en runtime de la regla SSH vía IAP
  - Revalidación en runtime de la configuración segura de Cloud NAT

Separación de responsabilidades:
- `security.rego`: validación estática/local del código Terraform.
- `plan-security.rego`: validación runtime del plan resuelto antes del apply.

## Autenticación CI/CD para Global

- El workflow `apply-global` usa una Service Account dedicada creada en el proyecto `bootstrap-476212`.
- Dicha Service Account es impersonada desde GitHub Actions mediante `OIDC / Workload Identity Federation (WIF)`.
- La cuenta está pensada para el alcance `global` de los proyectos destino, sin reutilizar el mismo state entre proyectos distintos.
- La Service Account activa para este flujo es una SA dedicada de global, por ejemplo `terraform-global-runner-v2@<bootstrap-project>.iam.gserviceaccount.com`.
- El provider WIF `github-provider` usa `google.subject = assertion.repository_id` para evitar depender del `sub` de GitHub, que cambia cuando el workflow usa GitHub Environments.
- El subject estable esperado para este repositorio es el `repository_id` numerico de GitHub, por lo que la SA debe permitir un principal con esta forma:
  - `principal://iam.googleapis.com/projects/<bootstrap-project-number>/locations/global/workloadIdentityPools/<pool-id>/subject/<repository-id>`

Permisos necesarios en `gcloud-live-staging` para este stack:
- `roles/compute.admin`
- `roles/serviceusage.serviceUsageAdmin`
- `roles/resourcemanager.projectIamAdmin`

Estos permisos cubren el alcance actual del entorno `global`:
- activación y gestión de APIs del proyecto
- bindings IAM de proyecto para OS Login / OS Admin / IAP
- firewall IAP SSH
- Cloud Router
- Cloud NAT

Permisos necesarios en `bootstrap-476212` para el state remoto:
- En la propia Service Account:
  - `roles/iam.workloadIdentityUser` para el principal estable del repositorio.
  - `roles/iam.serviceAccountTokenCreator` para el principal estable del repositorio.
  - `roles/iam.serviceAccountTokenCreator` para la propia Service Account.
- En el bucket de state remoto, por ejemplo `gs://<bootstrap-tfstate-bucket>`:
  - `roles/storage.objectAdmin` condicionado al prefijo `live/staging/global/`.
  - `roles/storage.legacyBucketReader` sobre el bucket para permitir el listado que necesita el backend GCS de Terraform.

Contexto del ajuste WIF:
- El provider anterior usaba `google.subject = assertion.sub`.
- Con `environment: Global`, GitHub emitía un subject como `repo:<owner>/<repo>:environment:Global`.
- Ese subject provocaba errores `iam.serviceAccounts.getAccessToken denied` al intentar impersonar la SA.
- El ajuste a `google.subject = assertion.repository_id` estabiliza la identidad federada y desacopla la impersonación del nombre del Environment.

## Cómo se aplica
Este stack se **aplicó desde consola** porque son recursos “one-off” (se crean una vez y luego se gestionan aquí).  
Igualmente se pueden usar workflows para mantener consistencia y trazabilidad.
