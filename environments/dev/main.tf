#####################################
# 1) ACTIVAR APIs
#####################################
resource "google_project_service" "compute" {
  project = var.project_id
  service = "compute.googleapis.com"
}

resource "google_project_service" "oslogin" {
  project    = var.project_id
  service    = "oslogin.googleapis.com"
  depends_on = [google_project_service.compute]
}

#####################################
# 2) OS LOGIN - METADATOS (seguros con *item*)
#####################################
resource "google_compute_project_metadata_item" "enable_oslogin" {
  project    = var.project_id
  key        = "enable-oslogin"
  value      = "TRUE"
  depends_on = [google_project_service.oslogin]
}

resource "google_compute_project_metadata_item" "enable_oslogin_2fa" {
  count      = var.enable_oslogin_2fa ? 1 : 0
  project    = var.project_id
  key        = "enable-oslogin-2fa"
  value      = "TRUE"
  depends_on = [google_project_service.oslogin]
}

resource "google_compute_project_metadata_item" "block_project_ssh_keys" {
  count      = var.block_project_ssh_keys ? 1 : 0
  project    = var.project_id
  key        = "block-project-ssh-keys"
  value      = "FALSE"
  depends_on = [google_project_service.oslogin]
}

#####################################
# 3) IAM para OS Login / OS Admin / IAP
#####################################
resource "google_project_iam_member" "oslogin" {
  for_each = toset(var.oslogin_members)
  project  = var.project_id
  role     = "roles/compute.osLogin"
  member   = each.value
}

resource "google_project_iam_member" "osadmin" {
  for_each = toset(var.osadmin_members)
  project  = var.project_id
  role     = "roles/compute.osAdminLogin"
  member   = each.value
}

resource "google_project_iam_member" "iap" {
  for_each = toset(var.iap_members)
  project  = var.project_id
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.value
}

#####################################
# 4) (Opcional) Firewall para IAP SSH (puerto 22)
#####################################
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-iap-ssh"
  network = "default" # cambia si usas tu VPC

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["iap-ssh"]
}

#####################################
# 4b) Cloud NAT (salida a Internet sin IP pública)
#####################################
resource "google_compute_router" "ubuntudev_router" {
  name    = "ubuntudev-router"
  network = "projects/${var.project_id}/global/networks/default"
  region  = var.region
}

resource "google_compute_router_nat" "ubuntudev_nat" {
  name                               = "ubuntudev-nat"
  router                             = google_compute_router.ubuntudev_router.name
  region                             = google_compute_router.ubuntudev_router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  enable_endpoint_independent_mapping = true

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

#####################################
# 5) VM Ubuntu 22.04 (4 vCPU / 8 GB)
#####################################
locals {
  vm_machine_type   = "${var.series}-custom-${var.vcpus}-${var.memory_mb}" # ej. e2-custom-4-8192
  ubuntu_2204_image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
}

resource "google_compute_instance" "ubuntu" {
  name         = var.vm_name
  zone         = var.zone
  machine_type = local.vm_machine_type

  # Permitir que Terraform pare la VM para aplicar cambios gordos.
  allow_stopping_for_update = true

  labels = {
    role    = "demo"
    os      = "ubuntu2204"
    managed = "terraform"
    env     = "dev"
  }

  # Etiqueta para la regla IAP SSH (si no usas IP pública)
  tags = ["iap-ssh"]

  boot_disk {
    initialize_params {
      image = local.ubuntu_2204_image
      size  = var.disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    network = "default"
    # IP pública opcional
    dynamic "access_config" {
      for_each = var.create_public_ip ? [1] : []
      content {}
    }
  }

  # No metas ssh-keys en metadatos; OS Login ya está a nivel proyecto
  metadata = {
    enable-oslogin = "FALSE"
  }

  service_account {
    email  = "default"
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot = true
  }
}

#####################################
# 6) Outputs útiles
#####################################
output "vm_name" {
  value = google_compute_instance.ubuntu.name
}

output "vm_zone" {
  value = google_compute_instance.ubuntu.zone
}

output "vm_internal_ip" {
  value = google_compute_instance.ubuntu.network_interface[0].network_ip
}

output "vm_external_ip" {
  value = try(google_compute_instance.ubuntu.network_interface[0].access_config[0].nat_ip, null)
}
