# Per-user values (no defaults): set in local.auto.tfvars (gitignored) or TF_VAR_* in CI.
variable "project_name" {
  description = "Project name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "admin_username" {
  description = "Admin user on the VMs"
  type        = string
}

variable "allowed_admin_cidrs" {
  description = "CIDRs allowed to reach SSH and the K3s API"
  type        = list(string)
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_public_key" {
  description = "SSH public key content (CI)"
  type        = string
  default     = null
}

variable "domain" {
  description = "Optional DNS name of the cluster"
  type        = string
  default     = ""
}

# Environment sizing: set in terraform.tfvars (committed).
variable "vnet_cidr" {
  description = "VNet address space"
  type        = string
}

variable "nodes_subnet_cidr" {
  description = "k3s-nodes subnet CIDR"
  type        = string
}

variable "server_vm_size" {
  description = "K3s server VM size"
  type        = string
}

variable "agent_vm_size" {
  description = "K3s agent VM size"
  type        = string
}

variable "agent_count" {
  description = "Number of agents"
  type        = number
}

variable "server_data_disk_gb" {
  description = "Server data disk size in GB"
  type        = number
}

variable "agent_data_disk_gb" {
  description = "Agent data disk size in GB"
  type        = number
}

variable "auto_shutdown_time" {
  description = "Daily shutdown HHMM UTC (null = never)"
  type        = string
  default     = null
}

variable "enable_key_vault" {
  description = "Create an optional Key Vault"
  type        = bool
  default     = false
}
