config {
  format = "default"
}

plugin "google" {
  enabled = true
  source  = "github.com/terraform-linters/tflint-ruleset-google"
  version = "0.37.1"
}

rule "terraform_required_version"    { enabled = true }
rule "terraform_unused_declarations" { enabled = true }
rule "terraform_comment_syntax"      { enabled = true }


