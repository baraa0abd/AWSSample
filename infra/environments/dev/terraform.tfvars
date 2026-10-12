# dev: burstable B-series, one agent, VMs stop every evening.
vnet_cidr           = "10.10.0.0/16"
nodes_subnet_cidr   = "10.10.1.0/24"
server_vm_size      = "Standard_B2ms" # 2 vCPU / 8 GiB: control plane + monitoring stack
agent_vm_size       = "Standard_B2s"  # 2 vCPU / 4 GiB
agent_count         = 1
server_data_disk_gb = 64
agent_data_disk_gb  = 32
auto_shutdown_time  = "1900"
