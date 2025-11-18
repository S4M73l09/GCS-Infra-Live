# GCS-Infra-Live

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

## Stack desplegado:

- `prometheus`
- `alertmanager`
- `node-exporter`
- `grafana` (con datasource de Prometheus preconfigurado)
- Reglas de alertas básicas + salud del host
- Alertas enviadas por correo vía Alertmanager

## 🐳 Stack Docker: docker-compose.yml

Servicios desplegados en el `docker-compose.yml`

Ruta: `ansible/files/monitoring/docker/docker-compose.yml`.

* prometheus
* alertmanager
* node-exporter
* grafana

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

## Artefacts y visibilidad
* Inventario y cfg quedan guardados como artifact:  
`ansible-inventory-env` → `ansible/hosts.ini`, `ansible/ansible.cfg`

* Puedes descargarlo desde la pestaña ***Actions*** del run correspondiente.

## Buenas prácticas que seguimos
* Sin llaves SSH ni 22 público: acceso por OS Login + IAP.
* Inventario efímero (on-the-fly) y sin IPs (solo FQDN GCE).
* Concurrencia en el workflow para evitar solapes.
* Jobs separados para máxima visibilidad (generate → publish → apply).
