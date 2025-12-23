packer {
  required_version = ">= 1.11.0"

  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = ">= 1.2.0"
    }
  }
}

# Variables (las pasas desde GitHub Actions con tus repo variables)
variable "project_id" { type = string }
variable "region"     { type = string } # (no la usa el builder directamente, pero la guardamos para consistencia)
variable "zone"       { type = string }

variable "network"    { type = string }
variable "subnetwork" { type = string }

# SA que usará el builder (impersonada vía OIDC desde el workflow)
variable "service_account_email" {
  type = string
}

# Tag para que coincida con tu firewall allow-ssh-iap
variable "iap_ssh_tag" {
  type    = string
  default = "iap-ssh"
}

# (Opcional) para que Terraform pueda usar siempre la última imagen por family
variable "image_family" {
  type    = string
  default = "ubuntu-2204-iap-family"
}

# Versión de k3s a hornear (no se arranca durante el build)
variable "k3s_version" {
  type    = string
  default = "v1.34.1+k3s1"
}

# Versiones pinneadas para reproducibilidad (ajusta periódicamente para aplicar parches)
variable "pkg_versions" {
  type = object({
    curl            : string
    git             : string
    ca_certificates : string
    jq              : string
  })
  default = {
    curl            = "7.81.0-1ubuntu1.20"
    git             = "1:2.34.1-1ubuntu1.11"
    ca_certificates = "20230311ubuntu0.22.04.1"
    jq              = "1.6-2.1ubuntu3"
  }
}

# Labels aplicados a la imagen final para trazabilidad
variable "image_labels" {
  type = map(string)
  default = {
    managed_by = "packer"
    os         = "ubuntu-2204"
    env        = "dev"
    purpose    = "image"
  }
}

# Labels para identificar recursos creados durante el build (GCP labels: lower-case key/value)
variable "build_labels" {
  type = map(string)
  default = {
    managed_by = "packer"
    os         = "ubuntu-2204"
    env        = "dev"
    purpose    = "image-build"
  }
}

locals {
  ts         = formatdate("YYYYMMDDhhmmss", timestamp())
  image_name = "ubuntu-2204-iap-${local.ts}"
}

source "googlecompute" "ubuntu2204_iap_nat" {
  project_id          = var.project_id
  zone                = var.zone
  service_account_email = var.service_account_email
  source_image_family = "ubuntu-2204-lts"
  image_storage_locations = [var.region]

  # SSH efímera: NO definimos ssh_private_key_file => Packer usa/genera key temporal para el build
  ssh_username = "packer"

  # Conexión por IAP (SSH via IAP)
  use_iap = true

  # VM temporal SIN IP pública (salida a Internet debe venir por Cloud NAT)
  omit_external_ip = true

  # Red/Subred privadas donde ya tienes Cloud NAT + firewall IAP->22 por tag
  network    = var.network
  subnetwork = var.subnetwork

  # Tags: firewall + identificación (network tags)
  tags = [
    var.iap_ssh_tag,
    "packer-dev"
  ]

  # Labels: organización y trazabilidad (key/value en minúsculas)
  labels = var.build_labels

  # Imagen resultante
  image_name   = local.image_name
  image_family = var.image_family
  image_labels = var.image_labels
}

build {
  name    = "ubuntu-2204-iap-nat"
  sources = ["source.googlecompute.ubuntu2204_iap_nat"]

  provisioner "shell" {
    inline = [
      "set -euxo pipefail",
      "export DEBIAN_FRONTEND=noninteractive",
      "sudo apt-get update -y",
      "sudo apt-get install -y \\",
        "curl=${var.pkg_versions.curl} \\",
        "git=${var.pkg_versions.git} \\",
        "ca-certificates=${var.pkg_versions.ca_certificates} \\",
        "jq=${var.pkg_versions.jq}",
      "sudo apt-mark hold curl git ca-certificates jq",
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",
      "lsb_release -a || true",
      # Instala k3s (server) pero sin arrancarlo; podrás habilitarlo con systemctl o script propio
      "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${var.k3s_version} INSTALL_K3S_SKIP_START=true sh -",
      "sudo systemctl disable --now k3s || true",
      # Config base de k3s (sin token; se inyecta en runtime)
      "sudo mkdir -p /etc/rancher/k3s",
      "cat <<'EOF' | sudo tee /etc/rancher/k3s/config.yaml",
      "write-kubeconfig-mode: \"0644\"",
      "disable:",
      "  - traefik",
      "  - servicelb",
      "flannel-backend: vxlan",
      "node-name: k3s-server-1",
      "cluster-cidr: 10.42.0.0/16",
      "service-cidr: 10.43.0.0/16",
      "EOF",
      "echo 'Packer provisioning finished.'"
    ]
  }
}
