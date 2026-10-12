# Architecture decision records

Short form: context -> decision -> consequence. Add new records at the bottom; never rewrite old ones.

## ADR-0: AWS instead of Azure
**Context.** The platform was first written for Azure, but no usable Azure subscription was
available. **Decision.** Port the provisioning layer to AWS; everything above it (K3s, app, Helm
chart, monitoring) is cloud-neutral and unchanged. **Consequence.** The Azure version remains in
git history (commit `4838430`). Azure Key Vault had no free-standing equivalent worth creating
and was dropped; secrets stay in SOPS.

## ADR-1: OpenTofu, compatible with Terraform >= 1.10
**Context.** Provisioning must be code and tool-neutral. **Decision.** Plain HCL with no
OpenTofu-only features and the `aws` 6.x provider pinned by the committed lock file. The minimum
version is 1.10 rather than the 1.6 originally requested, because that is where S3 state locking
without a DynamoDB table arrived. **Consequence.** Either binary works from 1.10 on.

## ADR-2: Remote state in S3 with native locking
**Context.** State holds every resource ID and must be shared and locked. **Decision.** One
versioned, encrypted, non-public bucket per account created by `infra/bootstrap/bootstrap.sh`, one
state key per environment, `use_lockfile` for locking. **Consequence.** No lock table to manage;
a bad apply can be undone by restoring an earlier object version.

## ADR-3: Private agents behind a NAT gateway
**Context.** Agents should not be reachable from the internet, but need outbound access.
**Decision.** The server sits in a public subnet with an Elastic IP; agents sit in a private
subnet whose default route is a NAT gateway. **Consequence.** About $35/month fixed cost even in
dev. Cheaper alternative if that matters: put agents in the public subnet with public IPs and
rely on the same security group.

## ADR-4: One composition module, thin environments
**Context.** dev and prod must be the same architecture at different sizes. **Decision.**
`modules/stack` wires `network`, `security`, `storage` and `compute`; `environments/{dev,prod}`
contain only a backend key and values. **Consequence.** Environments cannot drift structurally.

## ADR-5: Single K3s server with embedded etcd
**Context.** A one-server K3s defaults to SQLite, which has no online snapshot support.
**Decision.** Start the server with `cluster-init` (embedded etcd). **Consequence.** Scheduled
snapshots work today, and going HA later is "add two servers", not a datastore migration. Until
then the control plane is a single point of failure: workloads keep running if it is down, but
nothing can be scheduled and ingress on its public IP is lost.

## ADR-6: Snapshots to S3 with the instance's IAM role
**Context.** Cluster state must survive the loss of the server. **Decision.** K3s' built-in S3
snapshot upload, authenticated by an instance role that can only touch the backup bucket.
**Consequence.** No credentials on disk and no extra software or timers.

## ADR-7: Helm for the app (not Kustomize)
**Context.** One packaging tool was requested. **Decision.** Helm. The monitoring stack is Helm
anyway, so there is a single tool, release history, and `--atomic` gives automatic rollback of a
failed rollout. **Consequence.** Templates are less readable than Kustomize patches; the chart is
kept small (5 template files) to compensate.

## ADR-8: SOPS + age for all secrets
**Context.** Ansible and Helm both need secrets, and nothing may be committed in clear text.
**Decision.** SOPS with one age key: encrypted Helm values in `secrets/<env>/*.enc.yaml`, and the
`community.sops` vars plugin enabled for Ansible (`*.sops.yml` in `group_vars`). Sealed-secrets was
rejected: it needs a running cluster to encrypt and does not help Ansible. **Consequence.** The age
key is the crown jewel - back it up. The K3s join token is not stored at all (read from the server
at run time).

## ADR-9: Accepted security-scanner exceptions
**Context.** checkov flags controls that cost more than they protect here. **Decision.** Skip, with
a reason per check in `infra/.checkov.yaml`: no VPC flow logs, no detailed EC2 monitoring,
AWS-managed instead of customer-managed encryption keys, no cross-region replication or access
logging on the backup bucket. **Consequence.** Each is a conscious prod hardening item.

## ADR-10: K3s built-ins are kept
**Context.** K3s ships Traefik, ServiceLB, local-path and metrics-server. **Decision.** Disable
nothing: Traefik is the ingress, ServiceLB binds 80/443 on the node (no AWS load balancer needed),
local-path stores PVs on the EBS data disk (`/mnt/data`), metrics-server feeds the HPA.
**Consequence.** PVs are node-local: a pod with a volume is tied to its node.

## ADR-11: Monitoring runs in-cluster
**Context.** The brief allows node_exporter on the hosts *if* monitoring is external.
**Decision.** kube-prometheus-stack in the cluster, which already deploys node-exporter as a
DaemonSet; there is therefore no `monitoring_agents` Ansible role. Loki runs as a single binary on
local disk; Alloy (not the deprecated Promtail) ships logs. **Consequence.** If the cluster is
down, so is its monitoring - CloudWatch integration is the listed next step.

## ADR-12: Images are built by CI, not on the cluster
**Context.** The brief asks for a Docker role for a build/management node. **Decision.** The role
exists and targets the `build` inventory group, which is empty by default; GitHub runners build the
image. K3s nodes run containerd only. **Consequence.** Add a host to `build` to get a build box.

## ADR-13: The admin user is `ubuntu`
**Context.** The brief has a configurable admin username. **Decision.** Use the user Ubuntu's AMIs
create. A custom name would need cloud-init user data for no security gain (login is key-only and
root is disabled either way). **Consequence.** One less variable.

## ADR-14: CI role has AdministratorAccess
**Context.** The pipeline creates IAM roles, VPC, EC2, S3 and Scheduler resources. **Decision.**
`infra/bootstrap/oidc.sh` attaches `AdministratorAccess` to a role that only this repository's
workflows can assume. **Consequence.** Simple, but broader than least privilege: scope it down or
add a permissions boundary before pointing it at an account that holds anything else.
