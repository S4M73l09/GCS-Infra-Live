package terraform.global.plan_security

import rego.v1
import future.keywords.in

critical_types := {
  "google_compute_firewall",
  "google_compute_router",
  "google_compute_router_nat",
  "google_project_service",
}

protected_services := {
  "compute.googleapis.com",
  "oslogin.googleapis.com",
}

deny contains msg if {
  some rc in input.resource_changes
  rc.type in {"google_compute_firewall", "google_compute_router", "google_compute_router_nat"}
  is_delete_or_replace(rc.change.actions)
  msg := sprintf("%s.%s: no se permite delete/replace en recursos globales de red compartida", [rc.type, rc.name])
}

deny contains msg if {
  some rc in input.resource_changes
  rc.type == "google_compute_firewall"
  after := rc.change.after
  after != null
  some allow in after.allow
  allow.protocol == "tcp"
  "22" in allow.ports
  after.source_ranges != ["35.235.240.0/20"]
  msg := sprintf("Firewall %s: en el plan SSH solo puede venir desde IAP 35.235.240.0/20", [rc.name])
}

deny contains msg if {
  some rc in input.resource_changes
  rc.type == "google_compute_firewall"
  after := rc.change.after
  after != null
  some allow in after.allow
  allow.protocol == "tcp"
  "22" in allow.ports
  not contains(after.target_tags, "iap-ssh")
  msg := sprintf("Firewall %s: en el plan SSH debe usar target_tags con iap-ssh", [rc.name])
}

deny contains msg if {
  some rc in input.resource_changes
  rc.type == "google_compute_router_nat"
  after := rc.change.after
  after != null
  not after.log_config.enable
  msg := sprintf("Cloud NAT %s: en el plan debe mantener log_config.enable=true", [rc.name])
}

deny contains msg if {
  some rc in input.resource_changes
  rc.type == "google_compute_router_nat"
  after := rc.change.after
  after != null
  not after.enable_endpoint_independent_mapping
  msg := sprintf("Cloud NAT %s: en el plan debe mantener enable_endpoint_independent_mapping=true", [rc.name])
}

is_delete_or_replace(actions) if {
  actions == ["delete"]
}

is_delete_or_replace(actions) if {
  actions == ["delete", "create"]
}

is_delete_or_replace(actions) if {
  actions == ["create", "delete"]
}