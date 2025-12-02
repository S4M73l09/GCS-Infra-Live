# Proyecto y región
variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
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

# VM
variable "vm_name" {
  type    = string
  default = "Ubuntu-dev"
}

variable "series" {
  type        = string
  description = "Familia de máquina (e2, n2, n2d...)"
  default     = "e2"
}

variable "vcpus" {
  type        = number
  description = "Número de vCPU (custom)"
  default     = 4
}

variable "memory_mb" {
  type        = number
  description = "Memoria en MB (custom)"
  default     = 8192
}

variable "disk_size_gb" {
  type    = number
  default = 30
}

variable "create_public_ip" {
  type        = bool
  description = "Crear IP pública (true) o solo IAP (false)"
  default     = false
}
