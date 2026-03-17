locals {
  # Ruta de la familia de imagen horneada por Packer (mismo proyecto)
  packer_image_family = "projects/${var.project_id}/global/images/family/${var.packer_image_family}"

  # Sufijo y etiqueta de entorno para separar staging/prod en un mismo proyecto
  env_suffix = "stg"
  env_label  = "staging"

  vpc_name    = "${var.vpc_name}-${local.env_suffix}"
  subnet_name = "${var.subnet_name}-${local.env_suffix}"
  vm_name     = "${var.vm_name}-${local.env_suffix}"
}

# VPC dedicada (no default)
resource "google_compute_network" "vpc" {
  name                    = local.vpc_name
  auto_create_subnetworks = false
}

# Subred privada
resource "google_compute_subnetwork" "private" {
  name          = local.subnet_name
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr
}

# Cloud Router
resource "google_compute_router" "nat_router" {
  name    = "nat-router-${var.region}-${local.env_suffix}"
  region  = var.region
  network = google_compute_network.vpc.self_link
}

# Cloud NAT (salida a internet para la subred privada)
resource "google_compute_router_nat" "nat" {
  name   = "cloud-nat-${var.region}-${local.env_suffix}"
  router = google_compute_router.nat_router.name
  region = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private.self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  # logs opcionales (utiles para debug)
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall: permitir SOLO IAP -> SSH (tcp/22) por tag
resource "google_compute_firewall" "allow_ssh_from_iap" {
  name    = "${local.vpc_name}-allow-ssh-iap"
  network = google_compute_network.vpc.name

  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags = [var.iap_ssh_tag]
}

# VM basada en la imagen horneada por Packer (sin IP publica, acceso por IAP/OS Login)
resource "google_compute_instance" "k3s_server" {
  name         = local.vm_name
  machine_type = var.vm_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = local.packer_image_family
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.self_link
    # Sin IP publica
  }

  tags = [var.iap_ssh_tag, "env-${local.env_suffix}"]

  labels = {
    env = local.env_label
  }

  service_account {
    email  = var.vm_service_account
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }
}

module "auto_stop_idle" {
  source        = "./modules/auto-stop-idle"
  project_id    = var.project_id
  region        = var.region
  zone          = var.zone
  instance_name = google_compute_instance.k3s_server.name
  instance_id   = google_compute_instance.k3s_server.instance_id
}
