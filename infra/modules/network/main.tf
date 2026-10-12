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

variable "vpc_cidr" {
  description = "VPC address space"
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR of the public subnet (K3s server / ingress, NAT gateway)"
  type        = string
}

variable "nodes_subnet_cidr" {
  description = "CIDR of the private k3s-nodes subnet (agents)"
  type        = string
}

variable "availability_zone" {
  description = "AZ for both subnets. One AZ: EBS data disks are AZ-bound."
  type        = string
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name_prefix}-vpc" }
}

# The VPC's default security group allows everything between its members: empty it so nothing
# can end up protected by it accidentally.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-default-unused" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

# Public subnet: only the K3s server (ingress + SSH jump host) and the NAT gateway live here.
# Instances get a public address only when one is attached explicitly (the server's Elastic IP).
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name_prefix}-public" }
}

# Private subnet: agents. No route from the internet; outbound goes through the NAT gateway.
resource "aws_subnet" "nodes" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.nodes_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name_prefix}-k3s-nodes" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.name_prefix}-nat-eip" }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = "${var.name_prefix}-natgw" }
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-public-rt" }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_route_table" "nodes" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-k3s-nodes-rt" }

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "nodes" {
  subnet_id      = aws_subnet.nodes.id
  route_table_id = aws_route_table.nodes.id
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "availability_zone" {
  description = "AZ the subnets (and therefore the nodes and their disks) live in"
  value       = var.availability_zone
}

output "public_subnet_id" {
  description = "Public subnet ID, usable once its internet route exists"
  value       = aws_route_table_association.public.subnet_id
}

output "nodes_subnet_id" {
  description = "Private k3s-nodes subnet ID, usable once its NAT route exists"
  value       = aws_route_table_association.nodes.subnet_id
}

output "nat_public_ip" {
  description = "Egress IP of the cluster"
  value       = aws_eip.nat.public_ip
}
