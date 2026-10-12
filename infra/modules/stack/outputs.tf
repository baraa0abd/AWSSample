output "server_public_ip" {
  description = "Public IP of the K3s server / ingress"
  value       = module.compute.server_public_ip
}

output "private_ips" {
  description = "Node name => private IP"
  value       = { for n in module.compute.nodes : n.name => n.private_ip }
}

output "nat_public_ip" {
  description = "Outbound IP of the cluster"
  value       = module.network.nat_public_ip
}

output "nodes_security_group_id" {
  description = "Security group of the cluster nodes"
  value       = module.security.nodes_security_group_id
}

output "backup_bucket" {
  description = "S3 bucket holding K3s snapshots"
  value       = module.storage.backup_bucket
}

output "inventory_file" {
  description = "Generated Ansible inventory"
  value       = local_file.inventory.filename
}

output "ssh_command" {
  description = "SSH to the server"
  value       = "ssh ${local.admin_username}@${module.compute.server_public_ip}"
}
