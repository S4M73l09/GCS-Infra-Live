
package main

import rego.v1
import future.keywords.in

required_labels := {"env", "managed", "role"}

is_create_or_update(actions) if {
  actions[_] == "create"
}

is_create_or_update(actions) if {
  actions[_] == "update"
}

deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "google_compute_instance"
  is_create_or_update(rc.change.actions)
  ni := rc.change.after.network_interface[_]
  ni.access_config[_]
  msg := sprintf("Plan crea/actualiza VM con IP publica: %s", [rc.address])
}

deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "google_compute_instance"
  is_create_or_update(rc.change.actions)
  rc.change.after.service_account.email == "default"
  msg := sprintf("Plan usa SA default en: %s", [rc.address])
}

deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "google_compute_instance"
  is_create_or_update(rc.change.actions)
  not rc.change.after.shielded_instance_config[0].enable_secure_boot
  msg := sprintf("Plan sin secure boot en: %s", [rc.address])
}

deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "google_compute_instance"
  is_create_or_update(rc.change.actions)
  k := required_labels[_]
  not rc.change.after.labels[k]
  msg := sprintf("Plan en %s sin label obligatoria: %s", [rc.address, k])
}

valid_plan_env_values := {"staging", "dev"}

deny contains msg if {
  rc := input.resource_changes[_]
  rc.type == "google_compute_instance"
  is_create_or_update(rc.change.actions)
  not valid_plan_env_values[rc.change.after.labels.env]
  msg := sprintf("Plan en %s con env invalido: %s", [rc.address, rc.change.after.labels.env])
}
