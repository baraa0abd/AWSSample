terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5"
    }
  }
}

variable "project_name" {
  description = "Project name; lowercase letters/digits/hyphens (used in every resource name)"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}$", var.project_name))
    error_message = "project_name must be 2-15 chars: lowercase letters, digits, hyphens."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "admin_username" {
  description = "Admin user on the VMs"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key (ignored when ssh_public_key is set)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_public_key" {
  description = "SSH public key content (set in CI instead of a path)"
  type        = string
  default     = null
}

variable "allowed_admin_cidrs" {
  description = "CIDRs allowed to reach SSH (22) and the K3s API (6443)"
  type        = list(string)
  validation {
    condition     = length(var.allowed_admin_cidrs) > 0 && alltrue([for c in var.allowed_admin_cidrs : can(cidrhost(c, 0)) && !endswith(c, "/0")])
    error_message = "allowed_admin_cidrs must be a non-empty list of valid CIDRs and may not be open to the world (/0)."
  }
}

variable "domain" {
  description = "Optional DNS name pointing at the server (added to the K3s API cert SANs)"
  type        = string
  default     = ""
}

variable "vnet_cidr" {
  description = "VNet address space"
  type        = string
}

variable "nodes_subnet_cidr" {
  description = "k3s-nodes subnet CIDR"
  type        = string
}

variable "management_subnet_cidr" {
  description = "Optional management subnet CIDR (null = not created)"
  type        = string
  default     = null
}

variable "server_vm_size" {
  description = "VM size of the K3s server"
  type        = string
}

variable "agent_vm_size" {
  description = "VM size of the K3s agents"
  type        = string
}

variable "agent_count" {
  description = "Number of K3s agents"
  type        = number
  validation {
    condition     = var.agent_count >= 0 && var.agent_count <= 20
    error_message = "agent_count must be between 0 and 20."
  }
}

variable "server_data_disk_gb" {
  description = "Server data disk size in GB"
  type        = number
  default     = 64
}

variable "agent_data_disk_gb" {
  description = "Agent data disk size in GB"
  type        = number
  default     = 32
}

variable "auto_shutdown_time" {
  description = "Daily VM shutdown time HHMM UTC (null = never)"
  type        = string
  default     = null
}

variable "enable_key_vault" {
  description = "Create an optional Key Vault"
  type        = bool
  default     = false
}

variable "inventory_path" {
  description = "Where to write the generated Ansible inventory"
  type        = string
}
