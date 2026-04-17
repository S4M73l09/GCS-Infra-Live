package main

deny[msg] {
  r := input.resource.google_compute_firewall[_]
  r.direction == "INGRESS"
  r.source_ranges[_] == "0.0.0.0/0"
  a := r.allow[_]
  a.ports[_] == "22"
  msg := sprintf("Firewall %s expone SSH (22) a Internet", [r.name])
}

deny[msg] {
  r := input.resource.google_compute_instance[_]
  not r.service_account.email
  msg := sprintf("VM %s sin service_account definida", [r.name])
}

deny[msg] {
  r := input.resource.google_compute_instance[_]
  r.service_account.email == "default"
  msg := sprintf("VM %s usa SA default; debe usar SA dedicada", [r.name])
}

deny[msg] {
  r := input.resource.google_compute_instance[_]
  not r.shielded_instance_config.enable_secure_boot
  msg := sprintf("VM %s sin Secure Boot habilitado", [r.name])
}
