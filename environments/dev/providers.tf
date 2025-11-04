# providers.tf
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

