output "resource_group_name" {
  description = "Resource group of this environment"
  value       = azurerm_resource_group.this.name
}

output "server_public_ip" {
  description = "Public IP of the K3s server / ingress"
  value       = module.compute.server_public_ip
}

output "server_fqdn" {
  description = "Azure DNS name of the server (usable as DOMAIN for TLS)"
  value       = module.compute.server_fqdn
}

output "private_ips" {
  description = "VM name => private IP"
  value       = { for n in module.compute.nodes : n.vm_name => n.private_ip }
}

output "nat_public_ip" {
  description = "Outbound IP of the cluster"
  value       = module.network.nat_public_ip
}

output "nodes_nsg_name" {
  description = "NSG protecting the nodes subnet"
  value       = module.security.nodes_nsg_name
}

output "backup_storage_account" {
  description = "Storage account holding K3s snapshots"
  value       = module.storage.backup_storage_account_name
}

output "key_vault_uri" {
  description = "Key Vault URI (null when disabled)"
  value       = module.storage.key_vault_uri
}

output "inventory_file" {
  description = "Generated Ansible inventory"
  value       = local_file.inventory.filename
}

output "ssh_command" {
  description = "SSH to the server"
  value       = "ssh ${var.admin_username}@${module.compute.server_public_ip}"
}
