#####################################
# 5) VM Ubuntu 22.04 (4 vCPU / 8 GB)
#####################################
locals {
  vm_machine_type   = "${var.series}-custom-${var.vcpus}-${var.memory_mb}" # ej. e2-custom-4-8192
  ubuntu_2204_image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
}

resource "google_compute_instance" "ubuntu" {
  name         = var.vm_name
  zone         = var.zone
  machine_type = local.vm_machine_type

  # Permitir que Terraform pare la VM para aplicar cambios gordos.
  allow_stopping_for_update = true

  labels = {
    role    = "demo"
    os      = "ubuntu2204"
    managed = "terraform"
    env     = "staging"
  }

  # Etiqueta para la regla IAP SSH (si no usas IP pública)
  tags = ["iap-ssh"]

  boot_disk {
    initialize_params {
      image = local.ubuntu_2204_image
      size  = var.disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    network = "default"
    # IP pública opcional
    dynamic "access_config" {
      for_each = var.create_public_ip ? [1] : []
      content {}
    }
  }

  # No metas ssh-keys en metadatos; OS Login ya está a nivel proyecto
  metadata = {
    enable-oslogin = "FALSE"
  }

  service_account {
    email  = "default"
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot = true
  }
}

#####################################
# 6) Outputs útiles
#####################################
output "vm_name" {
  value = google_compute_instance.ubuntu.name
}

output "vm_zone" {
  value = google_compute_instance.ubuntu.zone
}

output "vm_internal_ip" {
  value = google_compute_instance.ubuntu.network_interface[0].network_ip
}

output "vm_external_ip" {
  value = try(google_compute_instance.ubuntu.network_interface[0].access_config[0].nat_ip, null)
}
