# Habilita el plugin de Google para comprobar recursos/atributos válidos
plugin "google" {
  enabled = true
  version = "0.9.1" # ajusta a la última estable
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

# Reglas base (añade/ajusta según tu estilo)
config {
  format = "default"
  call_module_type = "all" # lint también módulos cuando los uses
}

# Ejemplos de reglas útiles (actívalas/ajústalas a tu gusto)
rule "terraform_required_version" {
  enabled = true
}
rule "terraform_module_pinned_source" {
  enabled = true
}
rule "terraform_unused_declarations" {
  enabled = true
}
