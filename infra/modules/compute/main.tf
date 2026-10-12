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

variable "nodes" {
  description = "Node name => { role = server|agent, size = instance type }. Exactly one server."
  type = map(object({
    role = string
    size = string
  }))
}

variable "public_subnet_id" {
  description = "Subnet of the server"
  type        = string
}

variable "nodes_subnet_id" {
  description = "Subnet of the agents"
  type        = string
}

variable "security_group_id" {
  description = "Security group attached to every node"
  type        = string
}

variable "data_disk_ids" {
  description = "Node name => EBS data volume ID"
  type        = map(string)
}

variable "backup_bucket_arn" {
  description = "Bucket the server may write etcd snapshots to"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for the admin user"
  type        = string
}

variable "os_disk_size_gb" {
  description = "Root volume size"
  type        = number
  default     = 30
}

variable "auto_shutdown_cron" {
  description = "EventBridge cron (UTC) at which all nodes are stopped, e.g. \"0 19 * * ? *\" (null = never)"
  type        = string
  default     = null
}

locals {
  server = one([for k, n in var.nodes : k if n.role == "server"])
}

# Ubuntu 24.04 LTS, published by Canonical.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "admin" {
  key_name   = "${var.name_prefix}-admin"
  public_key = var.ssh_public_key
}

# The server's identity: it may read/write etcd snapshots in the backup bucket, nothing else.
# K3s picks these credentials up from instance metadata; nothing is stored on disk.
resource "aws_iam_role" "server" {
  name = "${var.name_prefix}-server"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "server_backup" {
  name = "k3s-snapshots"
  role = aws_iam_role.server.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = var.backup_bucket_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${var.backup_bucket_arn}/*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "server" {
  name = "${var.name_prefix}-server"
  role = aws_iam_role.server.name
}

resource "aws_instance" "node" {
  for_each               = var.nodes
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = each.value.size
  subnet_id              = each.value.role == "server" ? var.public_subnet_id : var.nodes_subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.admin.key_name # SSH keys only; Ubuntu images have no password login
  iam_instance_profile   = each.value.role == "server" ? aws_iam_instance_profile.server.name : null
  ebs_optimized          = true
  tags                   = { Name = "${var.name_prefix}-${each.key}", role = each.value.role }

  # IMDSv2 only, and not reachable from inside pods (hop limit 1): a compromised container
  # cannot borrow the node's AWS credentials.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.os_disk_size_gb
    encrypted   = true
  }

  lifecycle {
    # A newer Ubuntu AMI must not replace running nodes; unattended-upgrades patches them in place.
    ignore_changes = [ami]
  }
}

# Static public IP for the server: it is the ingress node, the K3s API endpoint and the SSH jump host.
resource "aws_eip" "server" {
  domain   = "vpc"
  instance = aws_instance.node[local.server].id
  tags     = { Name = "${var.name_prefix}-server-eip" }
}

resource "aws_volume_attachment" "data" {
  for_each    = var.nodes
  device_name = "/dev/sdf" # shows up as an NVMe device; the Ansible `disks` role finds it by volume ID
  volume_id   = var.data_disk_ids[each.key]
  instance_id = aws_instance.node[each.key].id
}

# Cost control for dev: stop (not terminate) every node on a schedule. Start them again by hand.
resource "aws_iam_role" "shutdown" {
  count = var.auto_shutdown_cron == null ? 0 : 1
  name  = "${var.name_prefix}-auto-shutdown"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "shutdown" {
  count = var.auto_shutdown_cron == null ? 0 : 1
  name  = "stop-cluster-nodes"
  role  = aws_iam_role.shutdown[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ec2:StopInstances"
      Resource = [for i in aws_instance.node : i.arn]
    }]
  })
}

resource "aws_scheduler_schedule" "shutdown" {
  count               = var.auto_shutdown_cron == null ? 0 : 1
  name                = "${var.name_prefix}-auto-shutdown"
  schedule_expression = "cron(${var.auto_shutdown_cron})"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.shutdown[0].arn
    input    = jsonencode({ InstanceIds = [for i in aws_instance.node : i.id] })
  }
}

output "server_public_ip" {
  description = "Public IP of the server / ingress node"
  value       = aws_eip.server.public_ip
}

output "nodes" {
  description = "Node name => { name, role, private_ip, data_disk_device }"
  value = {
    for k, n in var.nodes : k => {
      name       = aws_instance.node[k].tags.Name
      role       = n.role
      private_ip = aws_instance.node[k].private_ip
      # Stable NVMe path derived from the volume ID: identical on every boot and instance type.
      data_disk_device = "/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${replace(aws_volume_attachment.data[k].volume_id, "-", "")}"
    }
  }
}
