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
# 2) IAM para OS Login / OS Admin / IAP
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
# 4) Firewall para IAP SSH (puerto 22)
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
# 5) Cloud NAT (salida a Internet sin IP pública)
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
