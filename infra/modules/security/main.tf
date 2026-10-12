terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

variable "name_prefix" {
  description = "<project>-<env> prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "VPC the security group belongs to"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR (K3s API from inside the VPC)"
  type        = string
}

variable "allowed_admin_cidrs" {
  description = "CIDRs allowed to reach SSH and the K3s API"
  type        = list(string)
}

locals {
  # name => rule. Security groups deny everything that is not listed.
  cidr_rules = merge(
    { for c in var.allowed_admin_cidrs : "ssh-admin-${c}" => { port = 22, cidr = c, description = "SSH from admin" } },
    { for c in var.allowed_admin_cidrs : "k3s-api-admin-${c}" => { port = 6443, cidr = c, description = "K3s API from admin" } },
    {
      "k3s-api-vpc" = { port = 6443, cidr = var.vpc_cidr, description = "K3s API from inside the VPC" }
      "http"        = { port = 80, cidr = "0.0.0.0/0", description = "HTTP to the ingress (ACME challenges, redirects)" }
      "https"       = { port = 443, cidr = "0.0.0.0/0", description = "HTTPS to the ingress" }
    },
  )
}

# One group for every cluster node. Agents have no public address, so the internet-facing
# rules only ever take effect on the server.
resource "aws_security_group" "nodes" {
  name        = "${var.name_prefix}-nodes-sg"
  description = "K3s cluster nodes"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-nodes-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "cidr" {
  for_each          = local.cidr_rules
  security_group_id = aws_security_group.nodes.id
  description       = each.value.description
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
}

# Node-to-node: flannel VXLAN 8472/udp, kubelet 10250, node-exporter 9100, ...
resource "aws_vpc_security_group_ingress_rule" "node_to_node" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "All traffic between cluster nodes"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.nodes.id
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.nodes.id
  description       = "Outbound: package installs, image pulls, S3"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

output "nodes_security_group_id" {
  description = "Security group of the cluster nodes (CI opens a temporary 6443 rule for its runner)"
  value       = aws_security_group.nodes.id
}
