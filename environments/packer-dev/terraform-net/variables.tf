variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type    = string
  default = "europe-west1-b"
}

variable "vpc_name" {
  type    = string
  default = "vpc-dev"
}

variable "subnet_name" {
  type    = string
  default = "subnet-dev-private"
}

variable "subnet_cidr" {
  type    = string
  default = "10.10.0.0/24"
}

variable "iap_ssh_tag" {
  type    = string
  default = "iap-ssh"
}

variable "vm_name" {
  type    = string
  default = "k3s-server-1"
}

variable "vm_machine_type" {
  type    = string
  default = "e2-medium"
}

variable "vm_service_account" {
  type = string
}
