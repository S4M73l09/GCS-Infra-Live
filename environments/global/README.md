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

## Cómo se aplica
Este stack se **aplicó desde consola** porque son recursos “one-off” (se crean una vez y luego se gestionan aquí).  
No es necesario añadirlo a los workflows en serie.
