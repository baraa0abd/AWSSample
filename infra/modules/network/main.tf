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

variable "vnet_cidr" {
  description = "VNet address space"
  type        = string
}

variable "nodes_subnet_cidr" {
  description = "CIDR of the k3s-nodes subnet"
  type        = string
}

variable "management_subnet_cidr" {
  description = "CIDR of the optional management subnet (null = not created)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "k3s-nodes"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.nodes_subnet_cidr]
  # Lets the backup storage account firewall allow this subnet by identity instead of by public IP.
  service_endpoints = ["Microsoft.Storage"]
  # Explicit egress only (NAT gateway below); Azure's implicit outbound IP is retired for new subnets.
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "management" {
  count                           = var.management_subnet_cidr == null ? 0 : 1
  name                            = "management"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.management_subnet_cidr]
  default_outbound_access_enabled = false
}

# Agents have no public IP; the NAT gateway gives them (and the server) outbound internet for
# package installs and image pulls.
resource "azurerm_public_ip" "nat" {
  name                = "${var.name_prefix}-nat-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  name                = "${var.name_prefix}-natgw"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "nodes" {
  subnet_id      = azurerm_subnet.nodes.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

output "vnet_id" {
  description = "VNet ID"
  value       = azurerm_virtual_network.this.id
}

output "nodes_subnet_id" {
  description = "k3s-nodes subnet ID"
  value       = azurerm_subnet.nodes.id
}

output "management_subnet_id" {
  description = "Management subnet ID (null when disabled)"
  value       = one(azurerm_subnet.management[*].id)
}

output "nat_public_ip" {
  description = "Egress IP of the cluster"
  value       = azurerm_public_ip.nat.ip_address
}
