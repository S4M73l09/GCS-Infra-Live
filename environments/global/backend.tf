terraform {
  backend "gcs" {
    bucket = "bootstrap-476212-tfstate" # <-- tu bucket
    prefix = "live/global"              # carpeta separada para este estado
  }
}
