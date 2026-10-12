# Per-user values (no defaults): set in local.mk -> TF_VAR_*, or TF_VAR_* in CI.
variable "project_name" {
  description = "Project name"
  type        = string
}

variable "region" {
  description = "AWS region"
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
variable "vpc_cidr" {
  description = "VPC address space"
  type        = string
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR"
  type        = string
}

variable "nodes_subnet_cidr" {
  description = "Private k3s-nodes subnet CIDR"
  type        = string
}

variable "server_instance_type" {
  description = "K3s server instance type"
  type        = string
}

variable "agent_instance_type" {
  description = "K3s agent instance type"
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

variable "auto_shutdown_cron" {
  description = "EventBridge cron (UTC) at which all nodes are stopped (null = never)"
  type        = string
  default     = null
}
