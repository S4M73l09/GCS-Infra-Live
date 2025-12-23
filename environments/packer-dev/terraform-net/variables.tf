variable "project_id" {
  type = string
}

variable "region" {
  type = string
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
