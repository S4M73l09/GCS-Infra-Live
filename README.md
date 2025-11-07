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

## ✅ TFLint en este repo (lint de Terraform)
Para mejorar la seguridad y de paso ver problemas de codigo en Terraform en sus diferentes archivos, añadi un archivo `.tflint`.

***Su objetivo:*** es detectar problemas de `Terraform` antes del `plan/Apply` (tipos, Recursos obsoletos, reglas del provider de google y en general de cualquier Provider, etc)

### Qué se añadio:
* Archivo de configuracion: `environments/dev/.tflint.hcl`
* Plugin de reglas de Google: `tflint-ruleset-google` (version ***exacta:*** `0.37.1`)
* Job en CI (workflow de plan):
  * `tflint --init`(descarga el plugin)
  * `tflint`(ejecuta el lint)

### Instalación local (opcional)  
```bash
# (Ubuntu/WSL) instalar unzip si falta
sudo apt-get update && sudo apt-get install -y unzip

# Instalar TFLint
curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
tflint --version

# Inicializar y ejecutar en el entorno dev
cd environments/dev
tflint --init
tflint
```  
### Problemas que aparecieron y cómo se arreglaron

1. `apt update` fallaba (NO_PUBKEY repo Google Cloud SDK)
   * Solucion: reimportar clave y actualizar:
  ```bash
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/google-cloud-sdk.gpg
    echo "deb [signed-by=/etc/apt/keyrings/google-cloud-sdk.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
     | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
    sudo apt-get update
  ```  

2. Faltaba `unzip` (el instalador de TFlint no podia descomprimir)
   * Solución: `sudo apt-get install -y unzip`  

3. Error TFLint ↔ Plugin Google por version de API incompatible
   * Causa: el plugin era antiguo para el TFLint instalado.
   * Solución: ***pinear versión exacta*** reciente en `.tflint.hcl`:
   ```hcl
    plugin "google" {
    enabled = true
    source  = "github.com/terraform-linters/tflint-ruleset-google"
    version = "0.37.1"   # ¡versión exacta, sin >=!
    }
   ```
   * Nota: borrar caché antes de de re-inicializar:
   ```bash
   rm -rf ~/.tflint.d/plugins || true
   tflint --init
   ```

4. 404 al inicializar el plugin
   * Causa: se usó `version = ">= X.Y.Z"` (TFLint no acepta rangos con `source`)
   * Solución: usar número exacto (p. ej.`0.37.1).

5. Avisos de lint en el código
   * Variables sin tipo (`project_id`, `region`) -> añadir `type` (y `default` si aplica):  
   ```hcl
   variable "project_id" { type = string }
   variable "region"     { type = string  default = "europe-west1" }
   ```  
   * Variable `labels` no usada -> usarla en recursos (`labels = var.labels`) o eliminarla

## Automatizar actualización del plugin (opcional)

Se añadio un Renovate (App) con `Renovate.json` en `main` para abrir PRs que actualicen la línea: 
```hcl
version = "X.Y.Z"
```  
en los `tflint.hcl`.
Configurado para apuntar a la rama de `feat/dev` y en modo ***Scan and Alert***


## Workflows

1) **`Live-Plan.yaml`** (rama **`feat/dev`**)

  * Trigger: `pull_request` (cambios en **`environments/**`**) y **`workflow_dispatch`**.
  * Hace: **`init (lockfile readonly)`** -> **`validate`** -> **`plan`** -> sube artefactos: **`tfplan.bin`** (aplicable) y **`tfplan.txt`** (legible).

  * ***Extras:*** selector de entorno por carpeta; inputs opcionales para modos forzados:
    * **`force_refresh=true`** -> **`refresh-only`**
    * **`replace_targets="addr1,addr2"** -> **`-replace`**
    * **`destroy=true`** -> **`-destroy`**
        (Restringido a mi usuario en **`workflow_dispatch`**)

2) **`Live-Apply.yaml`** (Vive en main)

  * Trigger: **`workflow_dispatch`** con input **`pr_number`** (y **`env_dir=dev`**).
  * Hace: resuelve el SHA del PR -> Descarga el artefacto del ultimo plan exitoso -> **`checkout`** de ese commit exacto -> **`init`** -> **`apply tfplan.bin`**.
  * Environment: **`dev`** con *Required reviewers* (aprobacion antes de aplicar)

## ✅ Estado actual (feat/dev)

  * Backend GCS funcionando (live/dev) ✔  
  * OIDC/WIF configurado y probado ✔  
  * Plan en PR con artefactos ✔  
  * Apply manual desde main (exact plan) ✔  
  * Lockfile versionado y CI en solo lectura ✔  
  * `tflint.hcl` para mejorar seguridad ✔  

