project_id = "gcloud-live-staging" # ←  proyecto LIVE
region     = "europe-west1"
zone       = "europe-west1-d"

# Nuestro usuario (SSH normal y sudo)
oslogin_members = ["user:saminfradevops@gmail.com"]
osadmin_members = ["user:saminfradevops@gmail.com"]

# Si vamos a entrar sin IP pública (IAP), descomenta y usa también la regla de firewall:
# iap_members = ["user:saminfradevops@gmail.com"]


# VM
vm_name          = "staging-oslogin-ubuntu"
machine_type     = "e2-standard-2" # 2 vCPU / 8 GB RAM
disk_size_gb     = 25
create_public_ip = false # true si queremos IP pública