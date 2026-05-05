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

## Cómo se aplica
Este stack se **aplicó desde consola** porque son recursos “one-off” (se crean una vez y luego se gestionan aquí).  
Igualmente se pueden usar workflows para mantener consistencia y trazabilidad.
