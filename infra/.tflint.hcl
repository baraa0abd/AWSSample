plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Environments must be destroyable (`make destroy`); prevent_destroy cannot be toggled per env.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
