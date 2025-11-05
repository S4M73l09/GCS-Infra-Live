# Infra LIVE – Rama de pruebas feat/dev (entorno dev)

Este documento deja constancia exacta de lo que hace la rama feat/dev: flujo de plan en PR, artefacto del plan, apply manual desde el plan (sin tocar main), estructura mínima de Terraform y requisitos en GCP/GitHub.

---

## 🎯 Objetivo  

* Desplegar infraestructura real en GCP para el entorno dev usando:  
  * Terraform con backend remoto en GCS (bootstrap-STATE-NAME, prefijo live/dev).
  * Autenticación OIDC (WIF) desde GitHub Actions (sin claves JSON).
  * Plan en PR (no aplica) + Apply manual que descarga el plan del PR y lo aplica exactamente.
* Mantener main limpio (opcional): el apply no requiere que main tenga los mismos .tf.

## 🧱 Estructura mínima
```bash
live-infra/  
├─ .github/workflows/  
│  └─  plan.yml                     # Plan en PR + workflow_dispatch, sube tfplan.bin/txt   
└─ environments/  
   └─ dev/  
      ├─ backend.tf                # Backend GCS (bucket + prefix)  
      ├─ versions.tf               # Versión de Terraform + providers  
      ├─ providers.tf              # Providers google/google-beta  
      ├─ variables.tf              # labels, etc.  
      ├─ main.tf                   # ejemplo: VPC vacía  
      ├─ terraform.tfvars          # project_id = gcloud-live-dev, region, labels  
      └─ .terraform.lock.hcl       # versionado en Git (¡importante!)  
```  
+ > **Nota:** El workflow de *apply* (**`apply.yml`**) vive en la **rama `main`** y se ejecuta manualmente (*workflow_dispatch*). Aunque el fichero esté en `main`, aplica **exactamente el plan** generado en el PR de `feat/dev` porque hace **checkout del commit del PR** y **descarga el artefacto `tfplan.bin`** de ese run.

## 🔐 Variables de Actions (repo → Settings → Actions → Variables)

* GCP_WORKLOAD_IDENTITY_PROVIDER
  **`projects/project_number/locations/global/workloadIdentityPools/github-pool-2/providers/github-provider`**

* GCP_SERVICE_ACCOUNT
  **`terraform-bootstrap@bootstrap-PROJECT_NAME.iam.gserviceaccount.com`**

Estas salen del Bootstrap. No son secretos (se guardan como Variables, no Secrets).

## Terraform (sujeto a cambios)

***backend.tf***
```hcl
terraform {
  backend "gcs" {
    bucket = "bootstrap-476212-tfstate"
    prefix = "live/dev"
  }
}
```  
***versions.tf***
```hcl
terraform {
  required_version = "~> 1.9.0"
  required_providers {
    google      = { source = "hashicorp/google",      version = "~> 5.42.0" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 5.42.0" }
  }
}
```
***providers.tf***
```hcl
variable "project_id" {}
variable "region"     { default = "europe-west1" }

provider "google" {
  project = var.project_id
  region  = var.region
}
provider "google-beta" {
  project = var.project_id
  region  = var.region
}
```  
***variables.tf***
```hcl
variable "labels" {
  type    = map(string)
  default = { managed_by = "terraform", env = "dev" }
}
```  
***main.tf*** ejemplo minimo seguro
```hcl
resource "google_compute_network" "vpc_dev" {
  name                    = "vpc-dev"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}
```  
***terraform.tfvars***
```hcl
project_id = "gcloud-live-dev"
region     = "europe-west1"
labels     = { managed_by = "terraform", env = "dev" }
```  
Lockfile: environments/dev/.terraform.lock.hcl está versionado para builds reproducibles.

Lockfile verificado para las siguiente plataformas para usarlos en distintos providers como:

* Windows   
* Linux  
* MacOs  

Utilizamos el `terraform init` el cual genera el archivo de .terraform.lock, este es de vital importancia para el flujo de trabajo y es generado propiamente en cada entorno, por eso para añadir los providers necesarios hacemos un:
```hcl
terraform providers lock \
  -platform=linux_amd64 \
  -platform=linux_arm64 \
  -platform=darwin_arm64 \
  -platform=darwin_amd64 \
  -platform=windows_amd64
```
***Una Nota:*** Google no soporta el uso de Windows ARM a fecha del dia actual donde se publica esto. En el futuro puede cambiar.


## ☁️ Requisitos en GCP

* Proyecto LIVE: gcloud-live-dev con facturación vinculada.

* API habilitada: ***compute.googleapis.com.***

* Service Account del bootstrap con permisos en el proyecto LIVE:
  * roles/compute.networkAdmin (para la VPC de prueba).

* Bucket del state: PROJECT_NAME-tfstate con binding condicional por prefijo:
  * Condición: **resource.name.startsWith('projects/_/buckets/state_name_Bootstrap/objects/live/dev/')**

## 🔄 CI/CD de la rama `feat/dev`

### 2) Apply manual desde el plan del PR (**workflow definido en `main`**)

**Archivo:** `.github/workflows/apply.yml` **(en la rama `main`)**

1. Resuelve **SHA** del commit del PR y localiza el **último run exitoso** de `terraform-plan`.  
2. **Checkout del commit del PR** (no del `main`).  
3. Descarga los artefactos `tfplan.bin/txt` de ese run.  
4. `terraform init` al mismo backend y **`terraform apply tfplan.bin`** (exactamente el plan revisado).

- **Environment:** `dev` (configura *Required reviewers* para gate de aprobación).

**Aclaración de flujo:**  
- La **rama de pruebas (`feat/dev`)** contiene el código de Terraform y el **`plan.yml`** que genera el plan y los artefactos.
- La **rama `main`** contiene **`apply.yml`**. Al ejecutarlo manualmente, **no requiere merge**: toma el **plan del PR** y el **código exacto del commit del PR**, permitiendo mantener `main` limpia.

