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

variable "location" {
  description = "Azure region"
  type        = string
}

variable "subnet_id" {
  description = "Subnet the node NICs join"
  type        = string
}

variable "nodes" {
  description = "Node name => { role = server|agent, size = VM SKU }. Exactly one server."
  type = map(object({
    role = string
    size = string
  }))
}

variable "data_disk_ids" {
  description = "Node name => managed data disk ID (attached at LUN 0)"
  type        = map(string)
}

variable "admin_username" {
  description = "Admin user on the VMs"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for the admin user"
  type        = string
}

variable "os_disk_type" {
  description = "OS disk SKU"
  type        = string
  default     = "StandardSSD_LRS"
}

variable "os_disk_size_gb" {
  description = "OS disk size"
  type        = number
  default     = 32
}

variable "auto_shutdown_time" {
  description = "Daily shutdown time HHMM (null = no auto-shutdown)"
  type        = string
  default     = null
}

variable "auto_shutdown_timezone" {
  description = "Windows timezone name for the shutdown schedule"
  type        = string
  default     = "UTC"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

locals {
  server = one([for k, n in var.nodes : k if n.role == "server"])
}

# Static public IP for the server: it is the ingress node, the K3s API endpoint and the SSH jump host.
resource "azurerm_public_ip" "server" {
  name                = "${var.name_prefix}-server-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  # Free <label>.<region>.cloudapp.azure.com name, usable for Let's Encrypt without owning a domain.
  domain_name_label = var.name_prefix
  tags              = var.tags
}

resource "azurerm_network_interface" "node" {
  for_each            = var.nodes
  name                = "${var.name_prefix}-${each.key}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic" # stable for the lifetime of the NIC
    public_ip_address_id          = each.value.role == "server" ? azurerm_public_ip.server.id : null
  }
}

resource "azurerm_linux_virtual_machine" "node" {
  for_each                        = var.nodes
  name                            = "${var.name_prefix}-${each.key}"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = each.value.size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.node[each.key].id]
  # Nodes are configured over SSH by Ansible only; no VM extensions.
  allow_extension_operations = false
  tags                       = merge(var.tags, { role = each.value.role })

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    # Resolved once at VM creation (no drift); unattended-upgrades keeps it patched afterwards.
    version = "latest"
  }

  # The server's identity uploads etcd snapshots to blob storage; no stored credentials.
  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {}
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  for_each           = var.nodes
  managed_disk_id    = var.data_disk_ids[each.key]
  virtual_machine_id = azurerm_linux_virtual_machine.node[each.key].id
  lun                = 0 # the Ansible `disks` role finds the disk by this LUN
  caching            = "None"
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "node" {
  for_each              = var.auto_shutdown_time == null ? {} : var.nodes
  virtual_machine_id    = azurerm_linux_virtual_machine.node[each.key].id
  location              = var.location
  enabled               = true
  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.auto_shutdown_timezone

  notification_settings {
    enabled = false
  }
}

output "server_public_ip" {
  description = "Public IP of the server / ingress node"
  value       = azurerm_public_ip.server.ip_address
}

output "server_fqdn" {
  description = "Azure-provided DNS name of the server"
  value       = azurerm_public_ip.server.fqdn
}

output "server_principal_id" {
  description = "Managed identity of the server VM"
  value       = azurerm_linux_virtual_machine.node[local.server].identity[0].principal_id
}

output "nodes" {
  description = "Node name => { vm_name, role, private_ip }"
  value = {
    for k, n in var.nodes : k => {
      vm_name    = azurerm_linux_virtual_machine.node[k].name
      role       = n.role
      private_ip = azurerm_network_interface.node[k].private_ip_address
    }
  }
}
