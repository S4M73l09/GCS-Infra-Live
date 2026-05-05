# Proyecto y región
variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

# OS Login
variable "oslogin_members" {
  type        = list(string)
  description = "Miembros con roles/compute.osLogin"
  default     = []
}

variable "osadmin_members" {
  type        = list(string)
  description = "Miembros con roles/compute.osAdminLogin (sudo)"
  default     = []
}

variable "iap_members" {
  type        = list(string)
  description = "Miembros con roles/iap.tunnelResourceAccessor (SSH vía IAP)"
  default     = []
}

