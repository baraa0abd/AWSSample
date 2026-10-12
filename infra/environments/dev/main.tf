terraform {
  # OpenTofu or Terraform. 1.10+ for native S3 state locking (no DynamoDB table).
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68" # exact version pinned in .terraform.lock.hcl
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  # Bucket and region come from backend.hcl (written by infra/bootstrap/bootstrap.sh).
  backend "s3" {
    key          = "dev.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

# Credentials come from the environment: `aws login` locally, OIDC in CI.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project     = var.project_name
      environment = "dev"
      managed_by  = "opentofu"
    }
  }
}

module "stack" {
  source = "../../modules/stack"

  project_name        = var.project_name
  environment         = "dev"
  region              = var.region
  ssh_public_key_path = var.ssh_public_key_path
  ssh_public_key      = var.ssh_public_key
  allowed_admin_cidrs = var.allowed_admin_cidrs
  domain              = var.domain

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidr   = var.public_subnet_cidr
  nodes_subnet_cidr    = var.nodes_subnet_cidr
  server_instance_type = var.server_instance_type
  agent_instance_type  = var.agent_instance_type
  agent_count          = var.agent_count
  server_data_disk_gb  = var.server_data_disk_gb
  agent_data_disk_gb   = var.agent_data_disk_gb
  auto_shutdown_cron   = var.auto_shutdown_cron

  inventory_path = "${path.module}/../../../ansible/inventories/dev/hosts.yml"
}

output "stack" {
  description = "All outputs of the dev stack"
  value       = module.stack
}
