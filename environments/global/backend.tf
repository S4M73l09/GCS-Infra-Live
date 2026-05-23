terraform {
  backend "gcs" {
    bucket = "bootstrap-476212-tfstate" # <-- tu bucket
    prefix = "live/dev/global"              # carpeta separada para este estado
  }
}
