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

variable "availability_zone" {
  description = "AZ of the nodes (EBS volumes must be in the same AZ as their instance)"
  type        = string
}

variable "data_disks" {
  description = "Node name => data disk size in GB"
  type        = map(number)
}

variable "backup_retention_days" {
  description = "Days to keep K3s snapshots in S3"
  type        = number
  default     = 30
}

variable "force_destroy_backups" {
  description = "Let `tofu destroy` delete a non-empty backup bucket (dev only)"
  type        = bool
  default     = false
}

data "aws_caller_identity" "current" {}

# One data disk per node: holds local-path PVs (Prometheus, Loki, app data).
resource "aws_ebs_volume" "data" {
  for_each          = var.data_disks
  availability_zone = var.availability_zone
  size              = each.value
  type              = "gp3"
  encrypted         = true
  tags              = { Name = "${var.name_prefix}-${each.key}-data" }
}

# K3s etcd snapshots land here (written by the server through its instance role).
resource "aws_s3_bucket" "backup" {
  # Bucket names are global: the account ID makes this one unique.
  bucket        = "${var.name_prefix}-k3s-backup-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.force_destroy_backups
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket                  = aws_s3_bucket.backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    id     = "expire-old-snapshots"
    status = "Enabled"
    filter {}
    expiration {
      days = var.backup_retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = var.backup_retention_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Refuse any request that is not over TLS.
resource "aws_s3_bucket_policy" "backup" {
  bucket = aws_s3_bucket.backup.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.backup.arn, "${aws_s3_bucket.backup.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.backup]
}

output "data_disk_ids" {
  description = "Node name => EBS volume ID"
  value       = { for k, d in aws_ebs_volume.data : k => d.id }
}

output "backup_bucket" {
  description = "S3 bucket holding K3s snapshots"
  value       = aws_s3_bucket.backup.id
}

output "backup_bucket_arn" {
  description = "ARN of the backup bucket"
  value       = aws_s3_bucket.backup.arn
}
