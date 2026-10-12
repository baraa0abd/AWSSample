terraform {
  required_version = ">= 1.6.0" # OpenTofu or Terraform

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.40" # exact version pinned in .terraform.lock.hcl
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  # Account/container come from backend.hcl (written by infra/bootstrap/bootstrap.sh).
  # Locking is native (blob lease); auth is Entra ID only, no storage keys.
  backend "azurerm" {
    key              = "prod.tfstate"
    use_azuread_auth = true
  }
}

# Subscription and credentials come from the environment: `az login` locally, OIDC (ARM_USE_OIDC) in CI.
provider "azurerm" {
  storage_use_azuread = true
  features {}
}

module "stack" {
  source = "../../modules/stack"

  project_name        = var.project_name
  environment         = "prod"
  location            = var.location
  admin_username      = var.admin_username
  ssh_public_key_path = var.ssh_public_key_path
  ssh_public_key      = var.ssh_public_key
  allowed_admin_cidrs = var.allowed_admin_cidrs
  domain              = var.domain

  vnet_cidr           = var.vnet_cidr
  nodes_subnet_cidr   = var.nodes_subnet_cidr
  server_vm_size      = var.server_vm_size
  agent_vm_size       = var.agent_vm_size
  agent_count         = var.agent_count
  server_data_disk_gb = var.server_data_disk_gb
  agent_data_disk_gb  = var.agent_data_disk_gb
  auto_shutdown_time  = var.auto_shutdown_time
  enable_key_vault    = var.enable_key_vault

  inventory_path = "${path.module}/../../../ansible/inventories/prod/hosts.yml"
}

output "stack" {
  description = "All outputs of the prod stack"
  value       = module.stack
}
