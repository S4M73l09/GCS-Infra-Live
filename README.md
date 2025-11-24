# GCS-Infra-Live ES -> [EN](README.en.md)

## Infra Apply + Ansible (post-apply) en rama main

Este documento resume los cambios realizados en main para ejecutar configuraciones de Ansible de forma segura después del terraform apply, usando `OS Login + IAP` (sin llaves SSH ni puerto 22 público) y un inventario generado `on-the-fly.`

## Qué se añadió
### 1) Workflow encadenado: Inventory-And-Ansible.yaml
* Ubicación: `.github/workflows/Inventory-And-Ansible.yaml`
* Se dispara automáticamente cuando el workflow `terraform-apply` finaliza con éxito.
* Hace 3 jobs separados (visibilidad “pro” en Actions):
   #### *1) generate_inventory*
     * Autentica en GCP vía OIDC.
     * Genera ansible/hosts.ini con las VMs RUNNING que tengan `labels.env=entorno (por defecto dev)`.
     * Crea `ansible/ansible.cfg` apuntando a `~/.ssh/config (gcloud + IAP)`.
     * Verifica que el inventario no contenga IPs (solo FQDN GCE).
     * Sube ambos ficheros como `artifact: ansible-inventory-env`.
   #### *2) publish_inventory*
     * Publica/eco del artifact listo (opcional, solo visibilidad).
   #### *3) run_ansible*
     * Descarga el artifact en `ansible/.`
     * Instala Ansible.
     * Ejecuta `ansible-playbook ansible/site.yml` usando `ANSIBLE_CONFIG=ansible/ansible.cfg`.  


#### Si queremos cubrir prod, añadimos prod a la matrix.env en los tres jobs.
---

### 2) Playbook mínimo de Ansible: ansible/site.yml
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
ansible/
  site.yml
  requirements.yml
  web/
    index.html
    style.css
  files/
    monitoring/
      docker/
        docker-compose.yml            # (Ya puesto)
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
          alertmanager.yml.j2         # (Plantilla que generara el Alertmanager.yml)s
```
---
## Cómo funciona el pipeline completo
1. Se hace merge a main y corre el `terraform-apply` (con revisión del environment si procede).
2. Al terminar OK, se lanza `inventory-and-ansible`:
   * **Job 1:** genera inventario por etiquetas y sube artifact.
   * **Job 2:** marca visibilidad del artifact (opcional).
   * **Job 3:** descarga el artifact en `ansible/` e invoca `ansible-playbook` contra tus hosts.
   * **Job 4:** Instala la coleccion necesaria de Ansible `community.docker`.

3. Despues de la ejecucion del pipeline `inventory-and-ansible`.

   - Instala Docker y el plugin de Docker Compose en la VM.
   - Copia el stack de monitoring a `/opt/monitoring`.
   - Renderiza la configuración de Alertmanager desde una plantilla usando **GitHub Secrets**.
   - Levanta (o actualiza) el stack con `docker compose` de forma idempotente.

## Estructura de carpetas en la VM

```makefile
- `/opt/monitoring`
  - `docker-compose.yml` (Prometheus, Alertmanager, Grafana, Blackbox, node-exporter, web)
  - `prometheus/`
    - `prometheus.yml`
    - `rules/alerts.yml`
  - `alertmanager/`
    - `alertmanager.yml`
  - `grafana/`
    - provisioning, datasources, dashboards, etc.
- `/opt/web01`
  - `index.html`
  - `styles.css`
  - (cualquier otro estático de la página)
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

Ruta: `ansible/files/monitoring/docker/docker-compose.yml`.

* `prometheus` -> recolecta métricas 
* `alertmanager` -> gestiona las alertas
* `node-exporter` -> métricas de sistema (CPU, RAM, disco, red)
* `grafana` -> visualizacion de metricas
* `web (Nginx)` -> sirve la web estática desde `/opt/web01` 
* `blackbox` -> Comprueba la disponibilidad HTTP de la web

## Redes Docker

* `monitoring` -> prometheus, Grafana, Alertmanager, node-exporter, blackbox.

* `web-01` -> Nginx (`web`) + blackbox (para poder sondear `http://web:80`).

El servicio `web` monta:

```yaml
volumes:
  - /opt/web01:/usr/share/nginx/html:ro
  ```  

## 📊 Prometheus: prometheus.yml + reglas

Ruta: `ansible/files/monitoring/prometheus/prometheus.yml`.

Scrapea:

* prometheus:9090

* alertmanager:9093

* node-exporter:9100

Carga reglas desde `/etc/prometheus/rules/*.yml`.

***Envía alertas a Alertmanager.***

### Reglas de alertas

Ruta: `ansible/files/monitoring/prometheus/rules/alerts.yml`.

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

Ruta: `ansible/files/monitoring/grafana/provisioning/datasources/datasource.yml`.

Datasource de Prometheus creado automáticamente al arrancar Grafana.

## 📬 Alertmanager: plantilla con SMTP y GitHub Secrets

Ruta: `ansible/templates/monitoring/alertmanager.yml.j2`

Alertmanager se configura a partir de una plantilla Jinja2.

Las credenciales SMTP se inyectan desde GitHub Secrets en el workflow de Ansible:

### Secrets en GitHub necesarios  
En Settings → `Secrets and variables` → `Actions`:

* `ALERT_SMTP_SMARTHOST` → ej. smtp.gmail.com:587

* `ALERT_SMTP_FROM` → correo remitente

* `ALERT_SMTP_USER` → usuario SMTP (normalmente el mismo correo)

* `ALERT_SMTP_PASS` → contraseña de aplicación del proveedor de correo

* `ALERT_SMTP_TO` → correo destino (si se omite, usa ALERT_SMTP_FROM)

El step de Ansible en el workflow pasa estos secrets al playbook como variables -e, que la plantilla usa para generar `alertmanager.yml` en la VM.

## Web estática

* Nginx sirve una página simple de portfolio/explicacion del proyecto:
   * Descripcion de la infraestructura (Terraform + GCP + Github Action + Ansible + Docker)
   * Embeds de video de youtube mostrando el Bootstrap/repo-Live de la infraestructura
   * Enlaces a los repositorios de ***Bootstrap*** y ***Infra-Live***
* El contenido HTML/CSS vive en el repo bajo `ansible/web` y se copia a `/opt/web01` mediante Ansible.

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
`ansible-inventory-env` → `ansible/hosts.ini`, `ansible/ansible.cfg`

* Puedes descargarlo desde la pestaña ***Actions*** del run correspondiente.

## Buenas prácticas que hemos seguido
* Sin llaves SSH ni 22 público: acceso por OS Login + IAP.
* Inventario efímero (on-the-fly) y sin IPs (solo FQDN GCE).
* Concurrencia en el workflow para evitar solapes.
* Jobs separados para máxima visibilidad (generate → publish → apply).

