terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
  }
}

variable "name_prefix" {
  description = "<project>-<env> prefix for resource names"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy into"
  type        = string
}

variable "resource_group_id" {
  description = "Resource group ID (seeds the globally-unique name suffix)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "data_disks" {
  description = "Node name => data disk size in GB"
  type        = map(number)
}

variable "data_disk_type" {
  description = "Managed disk SKU for data disks"
  type        = string
  default     = "StandardSSD_LRS"
}

variable "nodes_subnet_id" {
  description = "Subnet allowed through the backup storage firewall"
  type        = string
}

variable "allowed_admin_cidrs" {
  description = "Admin CIDRs allowed through the storage / Key Vault firewalls"
  type        = list(string)
}

variable "backup_retention_days" {
  description = "Days to keep K3s snapshots in blob storage"
  type        = number
  default     = 30
}

variable "enable_key_vault" {
  description = "Create an RBAC-mode Key Vault for secrets"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

data "azurerm_client_config" "current" {}

locals {
  # Storage account / Key Vault names are global and alphanumeric-only.
  suffix      = substr(sha1(var.resource_group_id), 0, 6)
  alnum_name  = replace(var.name_prefix, "-", "")
  backup_name = substr("${local.alnum_name}bkp${local.suffix}", 0, 24)
}

# One data disk per node: holds local-path PVs (Prometheus, Loki, app data).
resource "azurerm_managed_disk" "data" {
  for_each                      = var.data_disks
  name                          = "${var.name_prefix}-${each.key}-data"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  storage_account_type          = var.data_disk_type
  create_option                 = "Empty"
  disk_size_gb                  = each.value
  public_network_access_enabled = false
  network_access_policy         = "DenyAll"
  tags                          = var.tags
}

# K3s etcd snapshots land here (uploaded by the server VM's managed identity).
resource "azurerm_storage_account" "backup" {
  name                            = local.backup_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # Entra ID auth only
  tags                            = var.tags

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
  }

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [var.nodes_subnet_id]
    # Storage firewall rejects /32 CIDRs; single IPs must be bare.
    ip_rules = [for c in var.allowed_admin_cidrs : trimsuffix(c, "/32")]
  }
}

resource "azurerm_storage_container" "k3s_backups" {
  name                  = "k3s-snapshots"
  storage_account_id    = azurerm_storage_account.backup.id
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "backup" {
  storage_account_id = azurerm_storage_account.backup.id

  rule {
    name    = "expire-old-snapshots"
    enabled = true
    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["${azurerm_storage_container.k3s_backups.name}/"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = var.backup_retention_days
      }
      version {
        delete_after_days_since_creation = var.backup_retention_days
      }
    }
  }
}

resource "azurerm_key_vault" "this" {
  count                      = var.enable_key_vault ? 1 : 0
  name                       = substr("${local.alnum_name}kv${local.suffix}", 0, 24)
  resource_group_name        = var.resource_group_name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
  tags                       = var.tags

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    ip_rules                   = var.allowed_admin_cidrs
    virtual_network_subnet_ids = []
  }
}

output "data_disk_ids" {
  description = "Node name => managed disk ID"
  value       = { for k, d in azurerm_managed_disk.data : k => d.id }
}

output "backup_storage_account_id" {
  description = "Backup storage account ID"
  value       = azurerm_storage_account.backup.id
}

output "backup_storage_account_name" {
  description = "Backup storage account name"
  value       = azurerm_storage_account.backup.name
}

output "backup_container_name" {
  description = "Blob container holding K3s snapshots"
  value       = azurerm_storage_container.k3s_backups.name
}

output "key_vault_uri" {
  description = "Key Vault URI (null when disabled)"
  value       = one(azurerm_key_vault.this[*].vault_uri)
}
