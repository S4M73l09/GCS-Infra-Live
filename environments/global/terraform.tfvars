project_id = "gcloud-live-dev" # ←  proyecto LIVE
region     = "europe-west1"

# Nuestro usuario (SSH normal y sudo)
oslogin_members = ["user:saminfradevops@gmail.com"]
osadmin_members = ["user:saminfradevops@gmail.com"]

# Si vamos a entrar sin IP pública (IAP), descomenta y usa también la regla de firewall:
# iap_members = ["user:saminfradevops@gmail.com"]

# Opcionales
enable_oslogin_2fa     = false
block_project_ssh_keys = true
