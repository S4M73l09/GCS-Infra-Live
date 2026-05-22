package main

import rego.v1
import future.keywords.in

deny contains msg if {
  r := input.resource.google_compute_instance[_]
  not r.service_account.email
  msg := sprintf("VM %s sin service_account definida", [r.name])
}

deny contains msg if {
  r := input.resource.google_compute_instance[_]
  r.service_account.email == "default"
  msg := sprintf("VM %s usa SA default; debe usar SA dedicada", [r.name])
}

deny contains msg if {
  r := input.resource.google_compute_instance[_]
  not r.shielded_instance_config.enable_secure_boot
  msg := sprintf("VM %s sin Secure Boot habilitado", [r.name])
}
