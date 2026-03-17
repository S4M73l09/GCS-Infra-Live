terraform {
  backend "gcs" {
    bucket = "bootstrap-476212-tfstate"
    prefix = "live/staging/packer-dev/terraform-net"
  }
}