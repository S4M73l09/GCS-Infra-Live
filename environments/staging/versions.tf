# versions.tf
terraform {
  required_version = "~> 1.13.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.21.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.21.0"
    }
  }
}


