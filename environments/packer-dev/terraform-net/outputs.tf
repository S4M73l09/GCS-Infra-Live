output "network_name" {
  value = google_compute_network.vpc.name
}

output "subnetwork_name" {
  value = google_compute_subnetwork.private.name
}

output "region" {
  value = var.region
}

output "network_self_link" {
  value = google_compute_network.vpc.self_link
}

output "subnetwork_self_link" {
  value = google_compute_subnetwork.private.self_link
}

output "vm_name" {
  value = google_compute_instance.k3s_server.name
}

output "vm_internal_ip" {
  value = google_compute_instance.k3s_server.network_interface[0].network_ip
}
