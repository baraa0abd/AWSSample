# dev: one agent, nodes stop every evening. Both instance types are eligible on AWS free-plan accounts.
vpc_cidr             = "10.10.0.0/16"
public_subnet_cidr   = "10.10.0.0/24"
nodes_subnet_cidr    = "10.10.1.0/24"
server_instance_type = "m7i-flex.large" # 2 vCPU / 8 GiB: control plane + monitoring stack
agent_instance_type  = "c7i-flex.large" # 2 vCPU / 4 GiB
agent_count          = 1
server_data_disk_gb  = 64
agent_data_disk_gb   = 32
auto_shutdown_cron   = "0 19 * * ? *" # 19:00 UTC daily
