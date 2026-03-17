variable "project_id" {
  type = string
}

variable "zone" {
  type = string
}

variable "instance_name" {
  type = string
}

variable "enable_idle_policy" {
  type    = bool
  default = true
}

variable "idle_cpu_threshold" {
  type    = number
  default = 0.03
}

variable "idle_duration_seconds" {
  type    = number
  default = 7200
}

variable "region" {
  type = string
}

variable "instance_id" {
  type = string
}