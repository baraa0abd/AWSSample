# infra

OpenTofu (Terraform >= 1.6 compatible). Run through the root Makefile: `make bootstrap | plan | apply | output | destroy`.

- `bootstrap/bootstrap.sh` - creates the remote-state storage account and writes `backend.hcl` (once per subscription).
- `bootstrap/oidc.sh` - creates the Entra app and federated credentials GitHub Actions uses.
- `modules/network` - VNet, subnets, NAT gateway.
- `modules/security` - NSGs and their subnet associations.
- `modules/storage` - data disks, backup storage account, optional Key Vault.
- `modules/compute` - public IP, NICs, VMs, disk attachments, auto-shutdown.
- `modules/stack` - wires the four modules into one environment and generates the Ansible inventory.
- `environments/{dev,prod}` - backend key + sizing (`terraform.tfvars`). Per-user values come from `local.mk` as `TF_VAR_*`.

Checks: `tofu fmt -check -recursive .`, `tofu validate`, `tflint --recursive`, `checkov -d . --config-file .checkov.yaml`.
Accepted checkov exceptions are listed with reasons in `.checkov.yaml`.
