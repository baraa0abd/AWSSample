# prod: non-burstable general-purpose nodes, two agents, always on.
vpc_cidr             = "10.20.0.0/16"
public_subnet_cidr   = "10.20.0.0/24"
nodes_subnet_cidr    = "10.20.1.0/24"
server_instance_type = "m7i.large" # 2 vCPU / 8 GiB
agent_instance_type  = "m7i.large"
agent_count          = 2
server_data_disk_gb  = 128
agent_data_disk_gb   = 64
