# infra

OpenTofu (Terraform >= 1.10 compatible) for AWS. Run through the root Makefile: `make bootstrap | plan | apply | output | destroy`.

- `bootstrap/bootstrap.sh` - creates the remote-state S3 bucket and writes `backend.hcl` (once per account).
- `bootstrap/oidc.sh` - creates the OIDC provider and IAM role GitHub Actions assumes.
- `modules/network` - VPC, public and private subnet, internet and NAT gateways, routes.
- `modules/security` - the cluster nodes' security group and its rules.
- `modules/storage` - EBS data disks and the S3 bucket for K3s snapshots.
- `modules/compute` - key pair, instances, Elastic IP, disk attachments, server IAM role, auto-shutdown schedule.
- `modules/stack` - wires the four modules into one environment and generates the Ansible inventory.
- `environments/{dev,prod}` - backend key + sizing (`terraform.tfvars`). Per-user values come from `local.mk` as `TF_VAR_*`.

Checks: `tofu fmt -check -recursive .`, `tofu validate`, `tflint --recursive`, `checkov -d . --config-file .checkov.yaml`.
Accepted checkov exceptions are listed with reasons in `.checkov.yaml`.
