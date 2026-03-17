resource "google_service_account" "auto_stop_sa" {
  account_id   = "${var.instance_name}-auto-stop"
  display_name = "SA auto-stop idle VM"
  project      = var.project_id
}

resource "google_project_iam_member" "auto_stop_compute" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.auto_stop_sa.email}"
}

resource "google_project_iam_member" "auto_stop_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.auto_stop_sa.email}"
}