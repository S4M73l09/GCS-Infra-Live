terraform {
  backend "gcs" {
    bucket = "bootstrap-476212-tfstate" # <-- tu bucket
    prefix = "live/staging"                 # carpeta separada para este estado
  }
}
