package main

required_labels := {"env", "managed", "role"}

deny[msg] {
  r := input.resource.google_compute_instance[_]
  k := required_labels[_]
  not r.labels[k]
  msg := sprintf("VM %s sin label obligatoria: %s", [r.name, k])
}

deny[msg] {
  r := input.resource.google_compute_instance[_]
  r.labels.env != "staging"
  msg := sprintf("VM %s con env invalido: %s (esperado: staging)", [r.name, r.labels.env])
}
