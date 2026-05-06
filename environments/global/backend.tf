terraform {
  backend "gcs" {
    bucket = "bootstrap-476212-tfstate" # <-- tu bucket
    prefix = "live/staging/global"      # carpeta separada para este estado
  }
}
