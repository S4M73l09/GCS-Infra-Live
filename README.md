# Rama de pruebas (feat/dev) ES -> [EN](README.en.md)

Este documento deja constancia exacta de lo que hace la rama feat/dev: flujo de plan en PR, artefacto del plan, workflows, estructura mínima de Terraform y requisitos en GCP/GitHub.

En el indice se muestran dos tipos de recursos usados, los cuales no estan `relacionados entre si` son totalmente independientes y lo unico que comparten es solamente que usan Terraform y SA y OIDC especiale generados en Bootstrap.

Tanto Packer como Terraform usan su propio SA creado en el Bootstrap para separarlos por motivos de seguridad, todo lo demas es totalmente independiente en si.

---
# Indice de contenidos

<!-- toc -->

- [Infraestructura y plantilla Packer horneada.](#infraestructura-y-plantilla-packer-horneada)
  - [Packer (imagen Ubuntu 22.04 IAP + k3s)](#packer-imagen-ubuntu-2204-iap--k3s)
  - [Workflow GitHub Actions (feat-dev-packer-net-plan)](#workflow-github-actions-feat-dev-packer-net-plan)
  - [Terraform red packer-dev](#terraform-red-packer-dev)
  - [Notas rápidas k3s](#notas-rápidas-k3s)
- [Infraestructura General (Terraform)](#infraestructura-general-terraform)
  - [Objetivo](#objetivo)
  - [Estructura mínima](#estructura-mínima)
  - [Variables de Actions (repo → Settings → Actions → Variables)](#variables-de-actions-repo--settings--actions--variables)
  - [Terraform (sujeto a cambios)](#terraform-sujeto-a-cambios)
  - [Requisitos en GCP](#requisitos-en-gcp)
  - [CI/CD de la rama `feat/dev`](#ci-cd-de-la-rama-feat-dev)
  - [Verificación](#verificacion)
  - [TFLint en este repo (lint de Terraform)](#tflint-en-este-repo-lint-de-terraform)
  - [Automatizar actualización del plugin (opcional)](#automatizar-actualizacion-del-plugin-opcional)
  - [Workflows](#workflows)
  - [Video de demostracion del Workflow](#video-de-demostracion-del-workflow)
  - [✅ Estado actual (feat/dev)](#estado-actual-feat-dev)


<!-- tocstop -->

---
# Infraestrucutura y plantilla Packer.

<a id="infraestructura-y-plantilla-packer-horneada"></a>
## Infraestructura y plantilla Packer horneada.

<a id="packer-imagen-ubuntu-2204-iap--k3s"></a>
### Packer (imagen Ubuntu 22.04 IAP + k3s)
- **Packer (imagen Ubuntu 22.04 IAP + k3s)**  
  - `environments/packer-dev/gcp-ubuntu-2204-iap/packer.pkr.hcl`: VM temporal sin IP pública (`omit_external_ip=true`, `use_internal_ip=true`) y acceso por IAP; red/subred por variables.  
  - SA explícita `service_account_email`; etiquetas en VM y en imagen (`image_labels`), `image_family` e `image_storage_locations` por región.  
  - Provisioner: instala paquetes con versiones fijadas (`curl`, `git`, `ca-certificates`, `jq`) y los bloquea; limpia caché APT.  
  - Hornea k3s `v1.34.1+k3s1` instalado pero detenido (`INSTALL_K3S_SKIP_START=true`); config base en `/etc/rancher/k3s/config.yaml` (desactiva traefik/servicelb, flannel vxlan, CIDRs 10.42/10.43, kubeconfig 0644, `node-name: k3s-server-1`). Token **no** embebido: se genera en runtime al arrancar el server.  
  - Conexión por IAP: usa etiquetas para firewall `iap-ssh` y tag `packer-dev`; VM efímera sin IP pública.

<a id="workflow-github-actions-feat-dev-packer-net-plan"></a>
### Workflow GitHub Actions (feat-dev-packer-net-plan)
- **Workflow GitHub Actions (feat-dev-packer-net-plan)**  
  - Rutas: `environments/packer-dev/**`, rama `feat/dev`. Concurrency activado.  
  - Job Terraform (solo plan) en `environments/packer-dev/terraform-net`, OIDC con `GCP_SERVICE_ACCOUNT`, sin apply.  
  - Job Packer (solo validate) depende del plan; OIDC con `GCP_PACKER_SERVICE`; envía `PKR_VAR_*` y `PKR_VAR_service_account_email`.  
  - `packer fmt` formatea (sin `-check`) para evitar fallos por estilo; `packer validate` sin build.

<a id="terraform-red-packer-dev"></a>
### Terraform red packer-dev
- **Terraform red packer-dev**  
  - `environments/packer-dev/terraform-net`: VPC dedicada, subred privada, Cloud Router + NAT, firewall IAP→SSH por tag `iap-ssh`.  
  - Outputs: nombres y `network_self_link`/`subnetwork_self_link` para pasar a otros módulos.  
  - Variables para project/region/vpc/subnet/cidr/tag; asume mismo proyecto para red y compute.

<a id="notas-rápidas-k3s"></a>
### Notas rápidas k3s
- **Notas rápidas k3s**  
  - k3s queda instalado y parado; al arrancar el server se genera token en `/var/lib/rancher/k3s/server/token` (o exporta `K3S_TOKEN` en runtime).  
  - Arranque server/agent se hace en runtime (cloud-init/script). No hay ingress/LB por defecto (traefik/servicelb deshabilitados).

### 🧱 Estructura minima de carpetas actual
```bash
live-infra/
├─ .github/workflows/  
│  └─ Live-plan.yml                     # Plan en PR + workflow_dispatch, sube tfplan.bin/txt
   └─ fea-dev-packer-net-plan.yaml 
└─ environments/  
   └─ dev/  
      ├─ backend.tf                # Backend GCS (bucket + prefix)  
      ├─ versions.tf               # Versión de Terraform + providers  
      ├─ providers.tf              # Providers google/google-beta  
      ├─ variables.tf              # labels, etc.  
      ├─ main.tf                   # ejemplo: VPC vacía  
      ├─ terraform.tfvars          # project_id = gcloud-live-dev, region, labels  
      └─ .terraform.lock.hcl       # versionado en Git (¡importante!)
   └─ packer-dev/  
      ├─ terraform-net/            # Red de terraform configurada para la plantilla
         ├─ main.tf
         ├─ outputs.tf
         └─ variables.tf
      └─ gcp-ubuntu-2204-iap/
        └─ packer.pkr.hcl          # Plantilla horneada para k3s y VM lista.
```

<a id="verificacion"></a>
## ✅ Verificacion 

Toda esta rama es de validacion/pruebas, lo cual permite depurar y mejorar la infraestructura. 

Todo esto funciona gracias al proyecto Bootstrap el cual tiene lo necesario para ampliar tanto SA como usar el OIDC propio de Google Cloud.

---

# Infraestructura general

<a id="infraestructura-general-terraform"></a>
## Infraestructura General (Terraform)

Aqui en este apartado se muestra dicha configuracion y validacion de los archivos .tf y workflows necesarios para la infraestructura no tenga errores de creacion. 

<a id="objetivo"></a>
### 🎯 Objetivo  

* Desplegar infraestructura real en GCP para el entorno dev usando:  
  * Terraform con backend remoto en GCS (bootstrap-STATE-NAME, prefijo live/dev).
  * Autenticación OIDC (WIF) desde GitHub Actions (sin claves JSON).
  * Plan en PR (no aplica) + Apply manual que descarga el plan del PR y lo aplica exactamente.
* Mantener main limpio (opcional): el apply no requiere que main tenga los mismos .tf.

<a id="estructura-mínima"></a>
### 🧱 Estructura mínima
```bash
live-infra/  
├─ .github/workflows/  
│  └─  plan.yml                      # Plan en PR + workflow_dispatch, sube tfplan.bin/txt   
   └─  feat-dev-packer-net-plan.yaml # Workflow para validar .tf y Packer.
└─ environments/  
   └─ dev/  
      ├─ backend.tf                # Backend GCS (bucket + prefix)  
      ├─ versions.tf               # Versión de Terraform + providers  
      ├─ providers.tf              # Providers google/google-beta  
      ├─ variables.tf              # labels, etc.  
      ├─ main.tf                   # ejemplo: VPC vacía  
      ├─ terraform.tfvars          # project_id = gcloud-live-dev, region, labels  
      └─ .terraform.lock.hcl       # versionado en Git (¡importante!)  
   └─ packer-dev
      ├─ terraform-net/
         ├─ main.tf
         ├─ outputs.tf
         └─ variables.tf
      └─ gcp-ubuntu-2204-iap/
        └─ packer.pkr.hcl
```  
+ > **Nota:** El workflow de *apply* (**`apply.yml`**) vive en la **rama `main`** y se ejecuta manualmente (*workflow_dispatch*). Aunque el fichero esté en `main`, aplica **exactamente el plan** generado en el PR de `feat/dev` porque hace **checkout del commit del PR** y **descarga el artefacto `tfplan.bin`** de ese run.

<a id="variables-de-actions-repo--settings--actions--variables"></a>
### 🔐 Variables de Actions (repo → Settings → Actions → Variables)

* GCP_WORKLOAD_IDENTITY_PROVIDER
  **`projects/project_number/locations/global/workloadIdentityPools/github-pool-2/providers/github-provider`**

* GCP_SERVICE_ACCOUNT
  **`terraform-bootstrap@bootstrap-PROJECT_NAME.iam.gserviceaccount.com`**

Estas salen del Bootstrap. No son secretos (se guardan como Variables, no Secrets).

<a id="terraform-sujeto-a-cambios"></a>
### Terraform (sujeto a cambios)

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


<a id="requisitos-en-gcp"></a>
### ☁️ Requisitos en GCP

* Proyecto LIVE: gcloud-live-dev con facturación vinculada.

* API habilitada: ***compute.googleapis.com.***

* Service Account del bootstrap con permisos en el proyecto LIVE:
  * roles/compute.networkAdmin (para la VPC de prueba).

* Bucket del state: PROJECT_NAME-tfstate con binding condicional por prefijo:
  * Condición: **resource.name.startsWith('projects/_/buckets/state_name_Bootstrap/objects/live/dev/')**

<a id="ci-cd-de-la-rama-feat-dev"></a>
### 🔄 CI/CD de la rama `feat/dev`

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

<a id="tflint-en-este-repo-lint-de-terraform"></a>
### ✅ TFLint en este repo (lint de Terraform)
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

6. auth@v2 → “must specify exactly one of workload_identity_provider or credentials_json”
   * El workflow usaba los secretos del repositorio en vez de las variables para el uso de OIDC y de la SA de Terraform
   * La solucion fue modificar dicha linea en el workflow para que use las variables `(vars.<variable_OIDC_GCP>)`

7. Error: ... unauthorized_client ... "credential is rejected by the attribute condition"
   * Este error ocurria porque la CEL del provider no coincidia con los claims reales (repo/branch/PR)
   * Solución: Fue Ajustar mapeos y condicion por ID de repo y ramas permitidas.  

   ***Mappings mínimos en el provider:***
```ini
  google.subject              = assertion.sub
  attribute.repository_id     = assertion.repository_id
  attribute.ref               = assertion.ref
  # (útiles)
  attribute.repository        = assertion.repository
  attribute.workflow          = assertion.workflow
  attribute.actor             = assertion.actor
  attribute.repository_owner  = assertion.repository_owner
```
   ***CEL final (dos repos por ID + main/feat/dev + PRs):***
```cel
attribute.repository_id in ["1089522719","1083637831"] &&
(
  attribute.ref == "refs/heads/main" ||
  attribute.ref == "refs/heads/feat/dev" ||
  matches(string(attribute.ref), "^refs/pull/")
)
```
Nota: Se usa `matches(string(...))` para evitar el error de tipos `dyn` con `startsWith` ya que google no acepta eso.

8. Bindings del repo `Live-Infra` en la SA de `Bootstrap`
   * Este error se debe a no colocar el binding correcto del repo `Live-Infra`
   * Solución: colocar dichos binding en la SA del `Bootstrap` apuntando al repo de ´Live-Infra`
```ruby
principalSet://iam.googleapis.com/projects/<BOOTSTRAP_PROJECT_NUMBER>/locations/global/workloadIdentityPools/<POOL_ID>/attribute.repository/S4M73l09/GCS-Infra-Live
principalSet://iam.googleapis.com/projects/<BOOTSTRAP_PROJECT_NUMBER>/locations/global/workloadIdentityPools/<POOL_ID>/attribute.repository/S4M73l09/GCS-Bootstrap---Live
```
***Rol: Usuario de identidades de carga de trabajo `(roles/iam.workloadIdentityUser)`***

9. `Unsupported Terraform Core version` (runner en 1.6.5 vs `required_version >= 1.8.0`)
   * Este error se debe a una version equivocada de Terraform en comparacion con la version requerida en el archivo de `versions.tf`
   * Solucion: `hashicorp/setup-terraform@v3` con `terraform_version: 1.9.7`, `terraform_wrapper: false`.
     * Verificación de versión en el job.
     * Pins de provider: `google`/`google-beta ~> 5.45`.
     * `terraform init -lockfile=readonly`.


<a id="automatizar-actualizacion-del-plugin-opcional"></a>
### Automatizar actualización del plugin (opcional)

Se añadio un Renovate (App) con `Renovate.json` en `main` para abrir PRs que actualicen la línea: 
```hcl
version = "X.Y.Z"
```  
en los `tflint.hcl`.
Configurado para apuntar a la rama de `feat/dev` y en modo ***Scan and Alert***


<a id="workflows"></a>
### Workflows

1) **`Live-Plan.yaml`** (rama **`feat/dev`**)

  * Trigger: `pull_request` (cambios en **`environments/**`**) y **`workflow_dispatch`**.
  * Hace: **`init (lockfile readonly)`** -> **`validate`** -> **`plan`** -> sube artefactos: **`tfplan.bin`** (aplicable) y **`tfplan.txt`** (legible).
  * TFLint con cache (`~/.tflint.d/plugins`), `tflint --init`, salida “pretty” y **SARIF** + subida a Code Scanning.
  * Cache de plugins de Terraform (`~/.terraform.d/plugin-cache`) y `terraform.rc`.

  * ***Extras:*** selector de entorno por carpeta; inputs opcionales para modos forzados:
    * **`force_refresh=true`** -> **`refresh-only`**
    * **`replace_targets="addr1,addr2"** -> **`-replace`**
    * **`destroy=true`** -> **`-destroy`**
        (Restringido a mi usuario en **`workflow_dispatch`**)
    * **`Infracost`** integrado (plan → comentario en PR).

2) **`Live-Apply.yaml`** (Vive en main)

  * Trigger: **`workflow_dispatch`** con input **`pr_number`** (y **`env_dir=dev`**).
  * Hace: resuelve el SHA del PR -> Descarga el artefacto del ultimo plan exitoso -> **`checkout`** de ese commit exacto -> **`init`** -> **`apply tfplan.bin`**.
  * Environment: **`dev`** con *Required reviewers* (aprobacion antes de aplicar)

<a id="video-de-demostracion-del-workflow"></a>
### Video de demostracion del Workflow

<video src="https://github.com/user-attachments/assets/27e975c5-c57c-48c8-925e-55249caee128" controls style="max-width: 100%; height: auto;"> Video demostracion de workflow </video>


Imagen que muestra esquema completo + artifacts

<p align="center">
  <img
    src="https://github.com/user-attachments/assets/b6f8dc87-ecc9-45f5-b366-da1f3958f867"
    alt="Imagen que muestra esquema completo + artifacts"
    style="max-width: 100%; height: auto;"
  />
</p>

<a id="estado-actual-feat-dev"></a>
### ✅ Estado actual (feat/dev)

  * `Backend GCS` funcionando (live/dev) ✔  
  * `OIDC/WIF` configurado y probado ✔  
  * Plan en PR con `artefactos` ✔  
  * Apply manual desde `main (exact plan)` ✔  
  * `Lockfile` versionado y CI en solo lectura ✔  
  * `tflint.hcl` para mejorar seguridad ✔  
  * `Infracost_api`añadido para visualizar costes ✔
