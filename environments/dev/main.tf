resource "google_compute_network" "vpc_dev" {
  name                    = "vpc-dev"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}
