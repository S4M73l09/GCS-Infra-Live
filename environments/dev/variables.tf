variable "labels" {
  type    = map(string)
  default = { managed_by = "terraform", env = "dev" }
}

