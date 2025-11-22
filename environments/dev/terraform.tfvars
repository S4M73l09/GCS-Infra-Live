project_id = "gcloud-live-dev" # ←  proyecto LIVE
region     = "europe-west1"
zone       = "europe-west1-a"

# Nuestro usuario (SSH normal y sudo)
oslogin_members = ["user:saminfradevops@gmail.com"]
osadmin_members = ["user:saminfradevops@gmail.com"]

# Si vamos a entrar sin IP pública (IAP), descomenta y usa también la regla de firewall:
# iap_members = ["user:saminfradevops@gmail.com"]

# Opcionales
enable_oslogin_2fa     = false
block_project_ssh_keys = true

# VM
vm_name          = "dev-oslogin-ubuntu"
series           = "e2"
vcpus            = 4
memory_mb        = 8192 # 8 GB exactos (custom)
disk_size_gb     = 30
create_public_ip = false # true si queremos IP pública