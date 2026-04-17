
package main

required_labels := {"env", "managed", "role"}

is_create_or_update(actions) {
  actions[_] == "create"
}

is_create_or_update(actions) {
  actions[_] == "update"
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.type == "google_compute_instance"
  is_create_or_update(rc.change.actions)
  ni := rc.change.after.network_interface[_]
  ni.access_config[_]
  msg := sprintf("Plan crea/actualiza VM con IP publica: %s", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.type == "google_compute_instance"
  is_create_or_update(rc.changes.actions)
  rc.change.after.service_account.email == "default"
  msg := sprintf("Plan usa SA default en: %s", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.type == "google_compute_instance"
  is_create_or_update(rc.changes.actions)
  not rc.change.after.shielded_instance_config.enable_secure_boot
  msg := sprintf("Plan sin secure boot en: %s", [rc.address])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.type == "google_compute_instance"
  is_create_or_update(rc.changes.actions)
  k := required_labels[_]
  not rc.change.after.labels[k]
  msg := sprintf("Plan en %s sin label obligatoria: %s", [rc.address, k])
}

deny[msg] {
  rc := input.resource_changes[_]
  rc.type == "google_compute_instance"
  is_create_or_update(rc.changes.actions)
  rc.change.after.labels.env != "staging"
  msg := sprintf("Plan en %s con env invalido: %s", [rc.address, rc.change.after.labels.env])
}
