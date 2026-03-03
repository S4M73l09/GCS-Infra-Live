output "project_id" {
  description = "GCP project ID used by global networking"
  value       = var.project_id
}

output "region" {
  description = "Region used by Cloud Router/NAT"
  value       = var.region
}

output "network_name" {
  description = "Name of the shared VPC network used by global resources"
  value       = "default"
}

output "network_self_link" {
  description = "Self link of the shared VPC network"
  value       = "projects/${var.project_id}/global/networks/default"
}

output "iap_ssh_firewall_name" {
  description = "Firewall rule allowing SSH from IAP"
  value       = google_compute_firewall.allow_iap_ssh.name
}

output "cloud_router_name" {
  description = "Cloud Router name"
  value       = google_compute_router.ubuntudev_router.name
}

output "cloud_nat_name" {
  description = "Cloud NAT name"
  value       = google_compute_router_nat.ubuntudev_nat.name
}

output "iap_ssh_firewall_self_link" {
  description = "Self link of the IAP SSH firewall rule"
  value       = google_compute_firewall.allow_iap_ssh.self_link
}

output "cloud_nat_self_link" {
  description = "Self link of Cloud NAT"
  value       = google_compute_router_nat.ubuntudev_nat.id
}
