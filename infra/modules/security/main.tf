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

variable "nodes_subnet_id" {
  description = "Subnet the nodes NSG is attached to"
  type        = string
}

variable "nodes_subnet_cidr" {
  description = "CIDR of the nodes subnet (node-to-node rule)"
  type        = string
}

variable "management_subnet_id" {
  description = "Optional management subnet to protect (null = none)"
  type        = string
  default     = null
}

variable "allowed_admin_cidrs" {
  description = "CIDRs allowed to reach SSH and the K3s API"
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

locals {
  # priority => rule. Everything not listed is dropped by DenyAllInbound, which also
  # overrides Azure's default AllowVnetInBound / AllowAzureLoadBalancerInBound.
  nodes_rules = {
    100 = { name = "AllowSshFromAdmin", protocol = "Tcp", ports = ["22"], sources = var.allowed_admin_cidrs }
    110 = { name = "AllowK3sApiFromAdmin", protocol = "Tcp", ports = ["6443"], sources = var.allowed_admin_cidrs }
    120 = { name = "AllowK3sApiFromVnet", protocol = "Tcp", ports = ["6443"], sources = ["VirtualNetwork"] }
    130 = { name = "AllowHttpHttpsFromInternet", protocol = "Tcp", ports = ["80", "443"], sources = ["Internet"] }
    # Node-to-node: flannel VXLAN 8472/udp, kubelet 10250, node-exporter 9100, ...
    140 = { name = "AllowNodeToNode", protocol = "*", ports = ["*"], sources = [var.nodes_subnet_cidr] }
  }
}

resource "azurerm_network_security_group" "nodes" {
  name                = "${var.name_prefix}-nodes-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_network_security_rule" "nodes" {
  for_each                    = local.nodes_rules
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.nodes.name
  name                        = each.value.name
  priority                    = each.key
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = each.value.protocol
  source_port_range           = "*"
  destination_port_ranges     = each.value.ports == ["*"] ? null : each.value.ports
  destination_port_range      = each.value.ports == ["*"] ? "*" : null
  # A service tag must be a single source_address_prefix; CIDR lists use the plural form.
  source_address_prefix      = length(each.value.sources) == 1 ? each.value.sources[0] : null
  source_address_prefixes    = length(each.value.sources) == 1 ? null : each.value.sources
  destination_address_prefix = "*"
}

resource "azurerm_network_security_rule" "nodes_deny_all" {
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.nodes.name
  name                        = "DenyAllInbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
}

resource "azurerm_subnet_network_security_group_association" "nodes" {
  subnet_id                 = var.nodes_subnet_id
  network_security_group_id = azurerm_network_security_group.nodes.id
}

# Optional management subnet: SSH from admins only.
resource "azurerm_network_security_group" "management" {
  count               = var.management_subnet_id == null ? 0 : 1
  name                = "${var.name_prefix}-mgmt-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  security_rule {
    name                       = "AllowSshFromAdmin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.allowed_admin_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "management" {
  count                     = var.management_subnet_id == null ? 0 : 1
  subnet_id                 = var.management_subnet_id
  network_security_group_id = azurerm_network_security_group.management[0].id
}

output "nodes_subnet_id" {
  description = "Nodes subnet ID, available only once the NSG is attached"
  value       = azurerm_subnet_network_security_group_association.nodes.subnet_id
}

output "nodes_nsg_name" {
  description = "Name of the nodes NSG (CI opens a temporary 6443 rule for its runner)"
  value       = azurerm_network_security_group.nodes.name
}
