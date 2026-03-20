# GCS-Infra-Live ES -> [EN](README.en.md)

> Nota: Esta rama es **staging**. Puede contener cambios y configuraciones de prueba antes de pasar a `main`.

## Version Staging - Probar workflows, configuraciones y demas - separado por entorno

## Version de Terraform por rama/worktree (tfenv)

Este repositorio usa un archivo `.terraform-version` para fijar la version de Terraform CLI por rama/worktree.

- Ejemplo (staging): `1.13.5`
- Comando de verificacion: `terraform version`
- Nota: el contenido del archivo debe ir **sin comillas** (ejemplo: `1.13.5`, no `"1.13.5"`).

Esto evita errores de compatibilidad con `required_version` en `versions.tf` y mantiene ejecuciones reproducibles en local y CI.



# Indice de contenidos
<!-- toc -->

- [Infra usando y horneando imagen Packer.](#infra-usando-y-horneando-imagen-packer)
  - [Workflow Packer + Terraform (feat/dev)](#workflow-packer-terraform-featdev)
  - [Imagen Packer horneada con k3s](#imagen-packer-horneada-con-k3s)
- [Infra Apply + Ansible (post-apply) en rama main](#infra-apply--ansible-post-apply-en-rama-main)
  - [Estado de salud del entorno](#Estado-de-salud-del-entorno)
  - [Qué se añadió](#qué-se-añadió)
  - [Requisitos](#requisitos)
  - [Estructura recomendada del repositorio (En proceso)](#estructura-recomendada-del-repositorio-en-proceso)
  - [Cómo funciona el pipeline completo](#cómo-funciona-el-pipeline-completo)
  - [Estructura de carpetas en la VM](#estructura-de-carpetas-en-la-vm)
  - [Stack desplegado](#stack-desplegado)
  - [Ansible site.yml](#ansible-siteyml)
  - [Stack Docker: docker-compose.yml](#Stack-Docker-docker-compose-yml)
  - [Conexion a la VM usando IAP y VS Code o cualquier otra herramienta.](#conexion-a-la-vm-usando-iap-y-vs-code-o-cualquier-otra-herramienta)
  - [Buenas prácticas que hemos seguido](#buenas-prácticas-que-hemos-seguido)
<!-- tocstop -->

# Infra usando y horneando imagen Packer.

En esta parte del documento se muestra la estructura y la creacion de recursos usando una plantilla packer y archivos .tf los cuales son generados al hacer un `pull_request` desde la rama de prueba a la Rama `main`. Cabe destacar que la verificacion de `packer`ya se hace en la propia rama de pruebas `feat/dev`.

La infraestructura usada a traves del packer es solo como aprendizaje y conocimiento, debido a la complejidad de dicha parte del proyecto, se mejorara y se seguira poco a poco.

## Workflow Packer + Terraform (feat/dev)
- Workflow: `.github/workflows/feat-dev-packer-net-plan.yaml`.
- Orden: Packer (init/fmt/validate) → Terraform (fmt/init/validate/plan) en `environments/packer-dev/terraform-net` (VPC, subred privada, NAT, firewall IAP y VM sin IP pública basada en la imagen de Packer).
- Imagen: familia `ubuntu-2204-iap-family` publicada por Packer en el proyecto `TF_VAR_project_id`.
- Variables: `GCP_INFRA_PROJECT_ID/REGION/ZONE/NETWORK/SUBNETWORK`, `GCP_VM_SERVICE_ACCOUNT` y SA de Packer (`GCP_PACKER_SERVICE`) se pasan como variables del repo.
- Apply final: se hace en el workflow de `main` (manual y con entorno protegido); en feat/dev solo se valida plan y Packer.

## Imagen Packer horneada con k3s
- Base: Ubuntu 22.04, sin IP pública, acceso por IAP, tags `iap-ssh`/`packer-dev`.
- K3s `v1.34.1+k3s1` instalado pero detenido (`INSTALL_K3S_SKIP_START=true`); config base en `/etc/rancher/k3s/config.yaml` (traefik/servicelb desactivados, flannel vxlan, CIDRs 10.42/10.43, `node-name: k3s-server-1`, kubeconfig 0644).
- Token **no** embebido: se genera en runtime al arrancar el server.
- Paquetes pinneados y hold (`curl`, `git`, `ca-certificates`, `jq`); caché APT limpia; imagen publicada en la familia `ubuntu-2204-iap-family`.
- Autenticación: Packer utiliza una `SA`diferente que la de `Terraform`para separar, tambien usa `IAP` + `firewall` para limitar el acceso.
- OS Login ahora mismo esta en `false`, pero mas adelante se puede activar sin problemas.
- Para consumir la imagen se indica la familia de esta `local.packer_image_family` se usa en `boot_disk`, si la imagen su publica en otro proyecto, se necesitaria cambiar el `project` en la misma ruta.

# Infra Apply + Ansible (post-apply) en rama main

Este documento resume los cambios realizados en main para ejecutar configuraciones de Ansible de forma segura después del terraform apply, usando `OS Login + IAP` (sin llaves SSH ni puerto 22 público) y un inventario generado `on-the-fly.`

> Nota: En CI usamos OS Login con **impersonación de la Service Account** para registrar la key temporal de SSH y obtener el usuario POSIX correcto.

## 🔍 Estado de salud del entorno

[![Health report](https://github.com/S4M73l09/GCS-Infra-Live/actions/workflows/health-report.yml/badge.svg)](https://github.com/S4M73l09/GCS-Infra-Live/actions/workflows/health-report.yml)

Esta linea es un ejemplo de justo utilizar `Python` para crear un sistema de alertas y reports que se guardan de normal en los artifacts de Github, esto no esta actualmente puesto debido a que al usar tunel IAP para la conexion de VM, es imposible ponerlo para que se conecte.

## Qué se añadió
### 1) Workflow encadenado: Inventory-And-Ansible.yaml
* Ubicación: `.github/workflows/Inventory-And-Ansible.yaml`
* Se dispara automáticamente cuando el workflow `terraform-apply` finaliza con éxito.
* Hace 3 jobs separados (visibilidad “pro” en Actions):
   #### *1) generate_inventory*
     * Autentica en GCP vía OIDC.
     * Genera `ansible/hosts.ini` (runtime temporal del job) con las VMs RUNNING que tengan `labels.env=entorno (por defecto dev)`.
     * Crea `ansible/ansible.cfg` (runtime temporal del job) apuntando a `~/.ssh/config (gcloud + IAP)`.
     * Verifica que el inventario no contenga IPs (solo FQDN GCE).
     * Sube ambos ficheros como `artifact: ansible-inventory-env`.
   #### *2) publish_inventory*
     * Publica/eco del artifact listo (opcional, solo visibilidad).
   #### *3) run_ansible*
     * Descarga el artifact en `ansible/.` (directorio runtime temporal del job)
     * Instala Ansible.
     * Ejecuta `ansible-playbook environments/staging/ansible/site.yml` usando `ANSIBLE_CONFIG=ansible/ansible.cfg`.  


#### Si queremos cubrir prod, añadimos prod a la matrix.env en los tres jobs.
---

### 2) Playbook mínimo de Ansible: environments/staging/ansible/site.yml
* Crea la estructura de carpetas en la VM bajo `/opt/monitoring`.
* Copia (si existen en el repo) los archivos de `Prometheus, Alertmanager, Grafana y Docker` hacia la VM.
---
## Requisitos

### Variables de repositorio (Settings → Variables)
* `GCP_WORKLOAD_IDENTITY_PROVIDER (WIF)`
* `GCP_SERVICE_ACCOUNT` (SA usado por OIDC)

### IAM necesarias para el identity que ejecuta los workflows
* `roles/compute.osAdminLogin` (o roles/compute.osLogin si no se necesita sudo)
* `roles/iap.tunnelResourceAccessor`

### Red/Firewall
* SSH solo por `IAP`
* OS Login activado (a nivel proyecto y/o VM): `enable-oslogin = TRUE`.

### Etiquetas
* Las VMs que deben entrar en el inventario deben tener `labels.env=dev` (o el entorno que se use).

## Estructura recomendada del repositorio (En proceso)
```bash
environments/dev                     # (Ya añadido por mergear a main)
environments/staging/ansible/
  site.yml
  requirements.yml
  web/
    index.html
    style.css
  files/
    monitoring/
      prometheus/
        prometheus.yml                # (ya puesto)
        rules/
          alerts.yml                  # (ya puesto)
      grafana/
        provisioning/
          datasources/
            datasource.yml            # (ya puesto)
          dashboards/
            ejemplo.json              # (ya puesto)
    template/
      monitoring/
        alertmanager.yml.j2         # (Plantilla que generara el Alertmanager.yml)
        docker-compose.yml.j2       # (Plantilla para docker-compose.yml)
README.md
README.en.md
renovate.json
```
---
## Cómo funciona el pipeline completo
1. Se hace merge a main y corre el `terraform-apply` (con revisión del environment si procede).
2. Al terminar OK, se lanza `inventory-and-ansible`:
   * **Job 1:** genera inventario por etiquetas y sube artifact.
   * **Job 2:** marca visibilidad del artifact (opcional).
   * **Job 3:** descarga el artifact en `ansible/` (runtime temporal) e invoca `ansible-playbook` contra tus hosts.
   * **Job 4:** Instala la coleccion necesaria de Ansible `community.docker`.

3. Despues de la ejecucion del pipeline `inventory-and-ansible`.

   - Instala Docker y el plugin de Docker Compose en la VM.
   - Copia el stack de monitoring a `/opt/monitoring`.
   - Renderiza la configuración de Alertmanager desde una plantilla usando **GitHub Secrets**.
   - Levanta (o actualiza) el stack con `docker compose` de forma idempotente.

## Estructura de carpetas en la VM

```makefile
/opt
├─ monitoring/
│  ├─ docker/                       # directorio de trabajo del compose
│  │  └─ docker-compose.yml         # generado por Ansible
│  ├─ prometheus/
│  │  ├─ prometheus.yml             # bind: ../prometheus/prometheus.yml -> /etc/prometheus/prometheus.yml
│  │  └─ rules/                     # bind: ../prometheus/rules -> /etc/prometheus/rules
│  ├─ alertmanager/
│  │  └─ alertmanager.yml           # bind: ../alertmanager/alertmanager.yml -> /etc/alertmanager/alertmanager.yml
│  └─ grafana/
│     └─ provisioning/              # bind: ../grafana/provisioning -> /etc/grafana/provisioning
│
├─ web01/                           # bind: /opt/web01 -> /usr/share/nginx/html (servicio web)
│   ├─ index.html
│   └─ style.css
│
└─ volumes (Docker-managed):
    ├─ prometheus-data              # volumen nombrado (datos de Prometheus)
    └─ grafana-data                 # volumen nombrado (datos de Grafana)
```


## Stack desplegado:

- `prometheus`
- `alertmanager`
- `node-exporter`
- `web (hosting simple)`
- `grafana` (con datasource de Prometheus preconfigurado)
- Reglas de alertas básicas + salud del host
- Alertas enviadas por correo vía Alertmanager

## Ansible site.yml

El playbook encargado de:

1. Instalar Docker + plugin de compose.

2. Crear directorios:
   * `monitoring_base_dir: /opt/monitoring`
   * `web01_base_dir: /opt/web01`

3. Copiar:
   * `docker-compose.yml` y ficheros de Prometheus, Alertmanager y Grafana a `/opt/monitoring`.
   * Contenido de `files/web/` (HTML/CSS) a `/opt/web01`.

4. Levantar o actualizar el stack:
```yaml
community.docker.docker_compose_v2:
  project_src: "{{ monitoring_base_dir }}"
  state: present
  remove_orphans: true
```

Cuando cambian los archivos de la web o del stack, se notifica al handler `restart monitoring stack` para recrear los contenedores.

## 🐳 Stack Docker: docker-compose.yml

Servicios desplegados en el `docker-compose.yml`


Ruta: `environments/staging/ansible/templates/monitoring/docker-compose.yml.j2`

En esta plantilla se usa justo lo necesario para el despliegue, se usa plantilla para que se puedan meter las variables de usuario de Grafana para mejor seguridad.

* `prometheus` -> recolecta métricas 
* `alertmanager` -> gestiona las alertas
* `node-exporter` -> métricas de sistema (CPU, RAM, disco, red)
* `grafana` -> visualizacion de metricas
* `web (Nginx)` -> sirve la web estática desde `/opt/web01` 
* `blackbox` -> Comprueba la disponibilidad HTTP de la web


Ademas añade buenas practicas: 

**Prometheus**

- Imagen `prom/prometheus`.
  - Expone `9090`.
  - Monta configuración y reglas como volúmenes **de solo lectura**.
  - Persiste datos en el volumen `prometheus-data`.
  - Healthcheck HTTP (`/-/healthy`).
  - Límites de recursos: ~0.5 CPU y 1 GB de RAM.

**Alertmanager**

- Imagen `prom/alertmanager`.
  - Expone `9093`.
  - Configuración montada como volumen **ro** desde `./alertmanager/alertmanager.yml`.
  - Healthcheck HTTP (`/-/healthy`).

**Node exporter**

- Imagen `prom/node-exporter`.
  - Expone `9100`.
  - Monta `/proc`, `/sys` y `/` en **solo lectura** para la recolección de métricas.
  - Comando ajustado para usar rutas host (`--path.rootfs`, etc.).

**grafana**

- Imagen `grafana/grafana-oss` (a fijar a versión estable).
  - Expone `3000`.
  - Healthcheck HTTP (`/api/health`).
  - Admin user/password se inyectan desde **secrets de GitHub** a través de Ansible:
    - `GF_SECURITY_ADMIN_USER="{{ lookup('env', 'GRAFANA_ADMIN_USER') | default('admin') }}"`
    - `GF_SECURITY_ADMIN_PASSWORD="{{ lookup('env', 'GRAFANA_ADMIN_PASSWORD') | default('admin') }}"`
  - Desactiva el registro de nuevos usuarios (`GF_USERS_ALLOW_SIGN_UP=false`).
  - Persistencia en el volumen `grafana-data`.
  - Provisioning montado desde `./grafana/provisioning`.

**Web (Nginx)**

- Imagen `nginx:alpine`.
  - Expone `80`.
  - Sirve el portfolio estático desde `/opt/web01` en la VM (montado **ro**).

**Blackbox**

- Imagen `prom/blackbox-exporter`.
  - Expone `9115`.
  - Healthcheck HTTP (`/-/healthy`).
  - Se conecta tanto a la red de monitoring como a la red de la web para poder sondear el portfolio.

### Redes y volumenes

- Redes:
  - `monitoring`: Prometheus, Alertmanager, Node Exporter, Grafana, Blackbox.
  - `web-01`: Nginx (web) y Blackbox.

- Volúmenes:
  - `prometheus-data`: datos de Prometheus.
  - `grafana-data`: datos de Grafana.


### Buenas practicas aplicadas a la plantilla de docker-compose.yml.j2

- **Separación de responsabilidades**: cada servicio en su contenedor (Prometheus, Alertmanager, Node Exporter, Grafana, Nginx, Blackbox).
- **Seguridad**:
  - Credenciales de Grafana gestionadas vía **GitHub Secrets + Ansible + plantilla Jinja2**, nunca en el repo.
  - Volúmenes de configuración montados en modo **read-only**.
  - `security_opt: no-new-privileges:true` en los servicios para reducir escalado de privilegios.
- **Recursos controlados**:
  - Límites de CPU y memoria para Prometheus y Grafana (`deploy.resources.limits`) para evitar que saturen la VM.
- **Gestión de logs**:
  - Driver `json-file` con rotación (`max-size: 10m`, `max-file: 3`) para no llenar el disco.
- **Observabilidad del propio stack**:
  - Healthchecks HTTP en Prometheus, Alertmanager, Grafana y Blackbox para detectar rápidamente estados no saludables.
- **Variables lookup('env')**:
  - Variables puestas en el workflow usando `Lookup('env')` para inyectarlas sin mostrar en las plantillas seleccionadas, mejorando la seguridad.


## 📊 Prometheus: prometheus.yml + reglas

Ruta: `environments/staging/ansible/files/monitoring/prometheus/prometheus.yml`.

Scrapea:

* prometheus:9090

* alertmanager:9093

* node-exporter:9100

Carga reglas desde `/etc/prometheus/rules/*.yml`.

***Envía alertas a Alertmanager.***

### Reglas de alertas

Ruta: `environments/staging/ansible/files/monitoring/prometheus/rules/alerts.yml`.

Incluye dos grupos de reglas:

* `infra_basic`: estado general de targets, Prometheus y Alertmanager.
* `host_health`: salud del host basada en métricas de `node_exporter` (**CPU**, **memoria**, **disco**, **filesystem read-only**, etc.).

* Ademas de añadir `blackbox` para la monitorizacion de la pagina web.  
   * blackbox interno:  
     * Target: `http://web:80`  
   * blackbox externo o publico(Cuando haya dominio + cloudflare):  
     * Target: `https://Nuestro-dominio.com`  

Ambos jobs usan `relabel_configs` para enviar las peticiones al `blackbox-exporter` en `blackbox:9115`.

## 📈 Grafana: datasource provisioning

Ruta: `environments/staging/ansible/files/monitoring/grafana/provisioning/datasources/datasource.yml`.

Datasource de Prometheus creado automáticamente al arrancar Grafana.

Ademas, Grafana usa `secrets and variables` para almacenar el usuario y la contraseña de este para mayor seguridad

## 📬 Alertmanager: plantilla con SMTP y GitHub Secrets

Ruta: `environments/staging/ansible/templates/monitoring/alertmanager.yml.j2`

Alertmanager se configura a partir de una plantilla Jinja2.

Las credenciales SMTP se inyectan desde GitHub Secrets en el workflow de Ansible:

### Secrets en GitHub necesarios  
En Settings → `Secrets and variables` → `Actions`:

* `ALERT_SMTP_SMARTHOST` → ej. smtp.gmail.com:587

* `ALERT_SMTP_FROM` → correo remitente

* `ALERT_SMTP_USER` → usuario SMTP (normalmente el mismo correo)

* `ALERT_SMTP_PASS` → contraseña de aplicación del proveedor de correo

* `ALERT_SMTP_TO` → correo destino (si se omite, usa ALERT_SMTP_FROM)

* `GRAFANA_ADMIN_USER` → Nombre de usuario de Grafana.

* `GRAFANA_ADMIN_PASSWORD` → Contraseña de administrador de Grafana.

El step de Ansible en el workflow pasa estos secrets al playbook como variables `lookup('env', '...')`, que la plantilla usa para generar `alertmanager.yml` en la VM y las variables de Grafana en el archivo de `docker-compose.yml`.

## Web estática

* Nginx sirve una página simple de portfolio/explicacion del proyecto:
   * Descripcion de la infraestructura (Terraform + GCP + Github Action + Ansible + Docker)
   * Embeds de video de youtube mostrando el Bootstrap/repo-Live de la infraestructura
   * Enlaces a los repositorios de ***Bootstrap*** y ***Infra-Live***
* El contenido HTML/CSS vive en el repo bajo `environments/staging/ansible/web` y se copia a `/opt/web01` mediante Ansible.

## Artifacts y visibilidad 

En cada run del workflow de `Ansible` al final de todo genera un artifact que se puede descargar el cual muestra el comando directo que se puede usar para conectarse a la VM usando su nombre real y demas utilizamdo `IAP-Tunnel`.

## Validacíon local (WSL)

Herramientas usadas para validar la configuracion antes de desplegar:

*  Ansible  
   * `ansible-playbook site.yml --syntax-check`

* Prometheus
   * `promtool check config files/monitoring/prometheus/prometheus.yml`
   * `promtool check rules files/monitoring/prometheus/rules/alerts.yml`

* Docker-compose
   * `docker-compose config` (desde `files/monitoring/docker`)

* YAML linting
   * `yamllint` sobre `prometheus.yml` y `alerts.yml` para limpiar espacios y comentarios

## Flujo de promoción de Terraform (`feat/dev` → `main`)

En este repo usamos las ramas así:

- `main` → rama **LIVE / producción**.  
- `feat/dev` → rama de **desarrollo y pruebas** (Terraform, workflows, README, etc.).  
- Ramas tipo `feat/tf-...` → ramas **temporales de promoción**, solo para llevar cambios de Terraform desde `feat/dev` a `main`.

La idea es:

> En `feat/dev` puedo tocar de todo.  
> A `main` solo llegan los cambios de Terraform que yo decido, a través de una rama de promoción.

---

### Pasos para subir cambios de Terraform a `main`

Supongamos que los `.tf` están en `environments/dev`.

1. **Trabajar normal en `feat/dev`**

   - Editar Terraform en `environments/dev`.
   - Probar, validar, hacer `terraform plan`, etc.
   - Hacer commits y `git push` a `feat/dev` hasta que la infra esté lista.

2. **Cuando los cambios de Terraform estén listos para producción**

   Crear una rama de promoción limpia desde `main`:

   ```bash
   # 1) Ir a main y actualizar
   git checkout main
   git pull origin main

   # 2) Crear rama de promoción (nombre de ejemplo)
   git checkout -b feat/tf-update-<descripcion>

Traer solo la carpeta de Terraform desde feat/dev:
```
git checkout feat/dev -- environments/dev
```

Comprobar qué ha cambiado:
```bash
git status
```
→ Aquí solo deberían aparecer archivos bajo `environments/dev`.

Hacer commit y subir la rama:
```bash
git add environments/dev
git commit -m "Actualizar Terraform desde feat/dev"
git push origin feat/tf-update-<descripcion>
```

3. **Crear el pull_request a `main`**

   - Abrir un PR: `feat/tf-update-description -> main`
   - Revisar el diff: solo deben aparecer archivos dentro de `envinronments/dev`
   - Dejar que se ejecuten los workflows
   - Si todo esta OK -> hacer merge a `main`

4. **Limpiar rama de promocion**

Una vez mergeado el PR:

```bash
# Borrar la rama local
git branch -d feat/tf-update-<descripcion>

# Borrar la rama en remoto (GitHub)
git push origin --delete feat/tf-update-<descripcion>
```

## ¿Por qué usamos directamente `feat/dev -> main`

El PR `feat/dev -> main` arrastraría todos los cambios de esa rama(README, workflows, pruebas, etc.), no solo Terraform.

Con este flujo: 

* `feat/dev` sigue siendo un **taller** donde se pueda tocar de todo.
* `main` solo recibe, mediante ramas de promocion (`feat/tf-...`), los cambios de Terraform que ya estan listos para la produccion.

## Artefacts y visibilidad
* Inventario y cfg quedan guardados como artifact:  
`ansible-inventory-env` → `ansible/hosts.ini`, `ansible/ansible.cfg` (artefactos runtime temporales)

* Puedes descargarlo desde la pestaña ***Actions*** del run correspondiente.

## Acceso a VM sin IP pública con IAP + VS Code Remote-SSH

Esta VM (`dev-oslogin-ubuntu`, `europe-west1-b`) **no tiene IP pública**.  
El acceso se hace solo por:

- **IAP (Identity-Aware Proxy)**  
- **SSH** con `ProxyCommand` que llama a `gcloud` en WSL  
- **VS Code Remote-SSH**  
- **Port forwarding** para Nginx / Prometheus / Grafana

---

## Demostracion de Infraestructura de Rama main

### Demostracion de Workflow de Terraform

 <video src="https://github.com/user-attachments/assets/bc6c77b1-89ce-4a6a-8a26-95e66cca89ec" controls muted playsinline style="max-width: 100%;"></video>

### Demostracion de Workflow de Ansible

<video src="https://github.com/user-attachments/assets/94ba4a33-5c7f-40f6-8cdd-ae9ee04fd263" controls muted playsinline style= "max-width: 100%;"></video>

#### Debido a las modificaciones de la Imagen usada en el workflow, tuve que cambiarla, y añadir diferentes mejorar al workflow para tener una estabilidad y control de versiones correctas.

- `manifest unknown` al tirar de `ghcr.io/googlecloudplatform/cloud-sdk:latest` -> cambie a imagen válida en `gcr.io`y ademas he fijado su digest.
- Digest incorrecto (config digest) -> reemplazo por `manifest digest` válido.
- `set: Illegal option -o pipefail`-> se fuerza a usar `shell: bash`en los jobs.
- `sudo: command not found`error debido al cambio de imagen del contenedor -> quitamos sudo.
- Error de compatibilidad: `community.docker`vs Ansible 2.10 -> Se sube la version de Ansible/ansible-core.
- `No matching distribution found for ansible==12.3.0`-> esa versión no existe en PyPI.
- `No matching distribution found for ansible-core==2.17.*` -> Python demasiado viejo en la imagen; se cambia a una nueva.
- `ERROR: externally-managed-environment` (PEP 668) -> instalados Ansible en un venv.
- `Could not parse resource []` al arrancar VMs -> corregimos parsing de `name/zone` con `zone.basename()` + `IFS=$'\t'`.

Esta serie de errores y modificaciones se dieron por el cambio de imagen del contenedor, ahora el workflow esta mas estructurado y mas dinamico.

### Captura de todo el docker compose

Aqui se muestra el contenedor Docker.  
<img width="1059" height="104" alt="Image" src="https://github.com/user-attachments/assets/f4c325c2-a145-4dfc-9da4-9855264f2d47"/>





## Conexion a la VM usando IAP y VS Code o cualquier otra herramienta.

## 1. Requisitos

### Local (Windows + WSL)

- Windows 10/11 con **OpenSSH Client**.
- **VS Code** + extensión **Remote - SSH**.
- **WSL2 Ubuntu** con:
  - Google Cloud SDK (`gcloud`) instalado.
  - Proyecto configurado:
    ```bash
    gcloud auth login
    gcloud config set project NAME-Project
    ```
  - Clave creada por `gcloud`:
    `/home/USUARIO/.ssh/google_compute_engine`

Copiar la clave de WSL a Windows:

```bash
mkdir -p /mnt/c/Users/USUARIO/.ssh
cp /home/USUARIO/.ssh/google_compute_engine \
   /mnt/c/Users/USUARIO/.ssh/google_compute_engine
```

### GCP

 - Proyecto: `Nombre del proyecto`
 - VM: `nombre-de-lav`
 - IAP habilitado + permisos para la cuenta que se conecta.

## 2. Configuracion de la VM

Archivo: `C:\Users\USUARIO\.ssh\config`

```sshconfig
Host gcp-dev-iap
    HostName compute.Numerosoltadoporcomandodryrun
    User USUARIO

    IdentityFile C:/Users/USUARIO/.ssh/google_compute_engine
    IdentitiesOnly yes

    # Túnel IAP usando gcloud en WSL
    ProxyCommand wsl /home/USUARIO/google-cloud-sdk/platform/bundledpythonunix/bin/python3 /home/USUARIO/google-cloud-sdk/lib/gcloud.py compute start-iap-tunnel nombre-de-la-vm %p --listen-on-stdin --project=nombre-del-proyecto --zone=zona-ubicada-de-la-VM --verbosity=warning

    # Túneles HTTP locales
    LocalForward 8080 localhost:80      # Nginx / web
    LocalForward 9090 localhost:9090    # Prometheus
    LocalForward 3000 localhost:3000    # Grafana
```
> - HostName compute.NUMEROLARGO sale de
>   - gcloud compute ssh nombre-de-la-VM --tunnel-through-iap --dry-run.

## 3. Probar conexión SSH 

En powershell:
```powershell
ssh gcp-dev-iap
```

Si funciona deberías ver:
```bash
Usuario@Nombre-de-la-VM:~$
```
Y mientras la sesión esté abierta:

- `http://localhost:8080` → Nginx / web

- `http://localhost:9090` → Prometheus

- `http://localhost:3000` → Grafana

## 4. Uso con VS Code Remote-SSH

  1. Abrir VS Code
  2. `Ctrl+Shift+P`
  3. Seleccionar `gcp-dev-iap`
  4. Esperar a que se instale el ***VS Code Server*** en la VM (Primera vez)
  5. Abajo a la izquierda debe poner: `SSH: gcp-dev-iap`.
  6. `Terminal -> New Terminal` -> prompt esperado
  ```bash
    USUARIO@Nombre-de-la-VM:~$
   ```
A partir de ahora: 

  - Se edita archivos directamente en la VM.
  - Usas la terminal remota para `docker`, logs, ect.
  - Accedes a los servicios vía `localhost:8080/9090/3000`.

## 5. Notas rápidas

  - Si Remote-SSH se rompe:  
  en la VM -> `rm -rf ~/.vscode-server` y volver a conectar.

  - Asegúremonos de tener `curl/wget` instalados en la VM para que VS Code pueda descargar el server:
  ```bash
  sudo apt update
  sudo apt install -y curl wget
  ```

Asi queda documentado el patrón: ***VM sin IAP pública + IAP + VS Code + túneles Locales***


## Buenas prácticas que hemos seguido
* Sin llaves SSH ni 22 público: acceso por IAP.
* Inventario efímero (on-the-fly) y sin IPs (solo FQDN GCE).
* Concurrencia en el workflow para evitar solapes.
* Jobs separados para máxima visibilidad (generate → publish → apply).
