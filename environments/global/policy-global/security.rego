# Reglas para el entorno actual de global

package terraform.global.security

deny contains msg if {
  some r in input.resource.google_compute_firewall
  some allow in r.allow
  allow.protocol == "tcp"
  "22" in allow.ports
  not r.source_ranges == ["35.235.240.0/20"]
  msg := sprintf("Firewall %s: SSH solo puede venir desde IAP 35.235.240.0/20", [r.name])
}

deny contains msg if {
  some r in input.resource.google_compute_firewall
  some allow in r.allow
  allow.protocol == "tcp"
  "22" in allow.ports
  not contains(r.target_tags, "iap-ssh")
  msg := sprintf("Firewall %s: SSH debe usar target_tags con iap-ssh", [r.name])
}

deny contains msg if {
  some r in input.resource.google_compute_router_nat
  not r.log_config.enable
  msg := sprintf("Cloud NAT %s: debe tener log_config.enable=true", [r.name])
}

deny contains msg if {
  some r in input.resource.google_compute_router_nat
  not r.enable_endpoint_independent_mapping
  msg := sprintf("Cloud NAT %s: debe tener enable_endpoint_independent_mapping=true", [r.name])
}

deny contains msg if {
  not service_enabled("compute.googleapis.com")
  msg := "Debe declararse google_project_service para compute.googleapis.com"
}

deny contains msg if {
  not service_enabled("oslogin.googleapis.com")
  msg := "Debe declararse google_project_service para oslogin.googleapis.com"
}

service_enabled(service) if {
  some __, r in input.resource.google_project_service
  r.service == service
}