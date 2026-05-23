# Proyecto y región
variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type = string

  validation {
    condition     = contains(var.allowed_zones, var.zone)
    error_message = "zone must be one of the allowed_zones for this environment."
  }
}

variable "allowed_zones" {
  type        = list(string)
  description = "Allowed zone for this Environment"
  default     = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
}

# Variable de Environment
variable "environment" {
  type        = string
  description = "Environment label used for resources and discovery"
  default     = "dev"

  validation {
    condition     = contains(["staging", "dev"], var.environment)
    error_message = "environment must be either staging or dev"
  }
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

variable "machine_type" {
  type        = string
  description = "Machine type used by the VM"
  default     = "e2-standard-2" # 2 vCPU / 8 GB RAM
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

variable "vm_service_account" {
  type        = string
  description = "Service Account usada por la VM"
}