terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  # Ruta de la familia de imagen horneada por Packer (mismo proyecto)
  packer_image_family = "projects/${var.project_id}/global/images/family/${var.packer_image_family}"
}

# VPC dedicada (no default)
resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

# Subred privada
resource "google_compute_subnetwork" "private" {
  name          = var.subnet_name
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr
}

# Cloud Router
resource "google_compute_router" "nat_router" {
  name    = "nat-router-${var.region}"
  region  = var.region
  network = google_compute_network.vpc.self_link
}

# Cloud NAT (salida a internet para la subred privada)
resource "google_compute_router_nat" "nat" {
  name   = "cloud-nat-${var.region}"
  router = google_compute_router.nat_router.name
  region = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private.self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  # logs opcionales (útiles para debug)
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall: permitir SOLO IAP -> SSH (tcp/22) por tag
resource "google_compute_firewall" "allow_ssh_from_iap" {
  name    = "${var.vpc_name}-allow-ssh-iap"
  network = google_compute_network.vpc.name

  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags = [var.iap_ssh_tag]
}

# VM basada en la imagen horneada por Packer (sin IP pública, acceso por IAP/OS Login)
resource "google_compute_instance" "k3s_server" {
  name         = var.vm_name
  machine_type = var.vm_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = local.packer_image_family
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.self_link
    # Sin IP pública
  }

  tags = [var.iap_ssh_tag]

  service_account {
    email  = var.vm_service_account
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }
}
