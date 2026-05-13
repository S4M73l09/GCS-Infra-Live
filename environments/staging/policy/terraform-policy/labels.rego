package main

import rego.v1
import future.keywords.in

required_labels := {"env", "managed", "role"}

deny contains msg if {
  r := input.resource.google_compute_instance[_]
  k := required_labels[_]
  not r.labels[k]
  msg := sprintf("VM %s sin label obligatoria: %s", [r.name, k])
}

valid_env_values := {"staging", "dev", "${var.environment}"}

deny contains msg if {
  r := input.resource.google_compute_instance[_]
  not valid_env_values[r.labels.env]
  msg := sprintf("VM %s con env invalido: %s", [r.name, r.labels.env])
}
