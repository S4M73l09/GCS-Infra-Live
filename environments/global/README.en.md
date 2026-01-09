# Global Terraform (project resources)

This stack contains **project-level global resources** shared by all environments (dev/staging). It should not be duplicated per environment.

## Managed resources
- Project APIs: `compute.googleapis.com`, `oslogin.googleapis.com`.
- Project metadata (managed outside Terraform):
  - `enable-oslogin`
  - `block-project-ssh-keys`
- OS Login IAM:
  - `roles/compute.osLogin`
  - `roles/compute.osAdminLogin`
- IAP SSH firewall: `allow-iap-ssh`.
- Cloud Router + Cloud NAT (egress without public IP).

## What was isolated here
These resources were previously defined inside environment stacks and were isolated to avoid collisions and duplicated state:
- Project metadata (kept outside this stack).
- OS Login/OS Admin IAM.
- IAP firewall.
- Router + NAT.

## What was imported
Existing project resources were imported into this global state to avoid recreation:
- `allow-iap-ssh` firewall.
- Existing Router and NAT.
- OS Login / OS Admin IAM.
- API services (`compute`, `oslogin`).

## How it is applied
This stack was **applied from the console/terminal** because these are “one-off” resources (created once and managed here).  
It does not need to be part of the CI workflow chain.
