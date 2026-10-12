# One environment = one resource group wiring network -> security -> storage -> compute,
# plus the generated Ansible inventory. environments/{dev,prod} only differ in the values they pass.

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  tags = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "opentofu"
  }

  nodes = merge(
    { "server-0" = { role = "server", size = var.server_vm_size, data_disk_gb = var.server_data_disk_gb } },
    { for i in range(var.agent_count) : "agent-${i}" => { role = "agent", size = var.agent_vm_size, data_disk_gb = var.agent_data_disk_gb } },
  )

  # CI passes the key itself; locally it is read from disk. try(): linters run without the key file.
  ssh_public_key = var.ssh_public_key != null ? var.ssh_public_key : try(file(pathexpand(var.ssh_public_key_path)), null)

  # Agents have no public IP: Ansible reaches them through the server.
  agent_ssh_args = "-o ProxyCommand=\"ssh -W %h:%p -q -o StrictHostKeyChecking=accept-new ${var.admin_username}@${module.compute.server_public_ip}\""
}

locals {
  inventory = {
    all = {
      vars = {
        ansible_user               = var.admin_username
        env                        = var.environment
        k3s_api_public_address     = module.compute.server_public_ip
        k3s_tls_sans               = compact([module.compute.server_public_ip, module.compute.server_fqdn, var.domain])
        k3s_backup_storage_account = module.storage.backup_storage_account_name
        k3s_backup_container       = module.storage.backup_container_name
        vnet_cidr                  = var.vnet_cidr
      }
      children = {
        k3s_server = {
          hosts = {
            for k, n in module.compute.nodes : n.vm_name => {
              ansible_host = module.compute.server_public_ip
              node_ip      = n.private_ip
            } if n.role == "server"
          }
        }
        k3s_agent = {
          hosts = {
            for k, n in module.compute.nodes : n.vm_name => {
              ansible_host            = n.private_ip
              node_ip                 = n.private_ip
              ansible_ssh_common_args = local.agent_ssh_args
            } if n.role == "agent"
          }
        }
        # Hosts that build images with Docker. Empty by default: CI runners build.
        build = { hosts = {} }
      }
    }
  }
}

resource "azurerm_resource_group" "this" {
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.tags

  lifecycle {
    precondition {
      condition     = local.ssh_public_key != null
      error_message = "No SSH public key: create ${var.ssh_public_key_path} (ssh-keygen -t ed25519) or set ssh_public_key."
    }
  }
}

module "network" {
  source                 = "../network"
  name_prefix            = local.name_prefix
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  vnet_cidr              = var.vnet_cidr
  nodes_subnet_cidr      = var.nodes_subnet_cidr
  management_subnet_cidr = var.management_subnet_cidr
  tags                   = local.tags
}

module "security" {
  source               = "../security"
  name_prefix          = local.name_prefix
  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  nodes_subnet_id      = module.network.nodes_subnet_id
  nodes_subnet_cidr    = var.nodes_subnet_cidr
  management_subnet_id = module.network.management_subnet_id
  allowed_admin_cidrs  = var.allowed_admin_cidrs
  tags                 = local.tags
}

module "storage" {
  source              = "../storage"
  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  resource_group_id   = azurerm_resource_group.this.id
  location            = azurerm_resource_group.this.location
  data_disks          = { for k, n in local.nodes : k => n.data_disk_gb }
  nodes_subnet_id     = module.network.nodes_subnet_id
  allowed_admin_cidrs = var.allowed_admin_cidrs
  enable_key_vault    = var.enable_key_vault
  tags                = local.tags
}

module "compute" {
  source              = "../compute"
  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  # Via the NSG association so VMs never boot on an unprotected subnet.
  subnet_id          = module.security.nodes_subnet_id
  nodes              = { for k, n in local.nodes : k => { role = n.role, size = n.size } }
  data_disk_ids      = module.storage.data_disk_ids
  admin_username     = var.admin_username
  ssh_public_key     = local.ssh_public_key
  auto_shutdown_time = var.auto_shutdown_time
  tags               = local.tags
}

resource "azurerm_role_assignment" "server_backup" {
  scope                = module.storage.backup_storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.compute.server_principal_id
}

# yamlencode instead of a hand-written template: cannot produce invalid YAML.
resource "local_file" "inventory" {
  filename        = var.inventory_path
  file_permission = "0644"
  content         = "# Generated by OpenTofu - do not edit.\n${yamlencode(local.inventory)}"
}
