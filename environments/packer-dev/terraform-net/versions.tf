terraform {
  required_version = "~> 1.13.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.21"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.5"
    }
  }
}
