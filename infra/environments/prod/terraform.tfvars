# prod: non-burstable D-series, two agents, always on, Key Vault enabled.
vnet_cidr           = "10.20.0.0/16"
nodes_subnet_cidr   = "10.20.1.0/24"
server_vm_size      = "Standard_D2s_v5" # 2 vCPU / 8 GiB
agent_vm_size       = "Standard_D2s_v5"
agent_count         = 2
server_data_disk_gb = 128
agent_data_disk_gb  = 64
enable_key_vault    = true
