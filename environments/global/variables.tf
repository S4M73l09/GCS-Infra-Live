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

variable "enable_oslogin_2fa" {
  type        = bool
  description = "Exigir 2FA para SSH vía OS Login (requiere 2SV en la cuenta)"
  default     = false
}

variable "block_project_ssh_keys" {
  type        = bool
  description = "Bloquear claves heredadas de metadatos del proyecto/instancia"
  default     = true
}
