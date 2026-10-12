# Architecture decision records

Short form: context -> decision -> consequence. Add new records at the bottom; never rewrite old ones.

## ADR-1: OpenTofu, compatible with Terraform >= 1.6
**Context.** Provisioning must be code and tool-neutral. **Decision.** Plain HCL with no
OpenTofu-only features, `required_version = ">= 1.6.0"`, the `azurerm` 4.x provider pinned by the
committed lock file. **Consequence.** Either binary works. The provider's 5.x line exists but is a
breaking upgrade; it is a deliberate future change, not something `init -upgrade` can pull in.

## ADR-2: Remote state in Azure Blob, Entra ID auth only
**Context.** State holds every resource ID and must be shared and locked. **Decision.** One storage
account per subscription created by `infra/bootstrap/bootstrap.sh`, one state key per environment,
blob-lease locking, versioning + 30-day soft delete, shared keys disabled. **Consequence.** No
storage key to leak; whoever runs tofu needs the *Storage Blob Data Contributor* role.

## ADR-3: Private agents behind a NAT gateway
**Context.** Agents should not be reachable from the internet, but need outbound access, and Azure
no longer gives new subnets implicit outbound connectivity. **Decision.** Only the server gets a
public IP; a NAT gateway provides egress for the subnet. **Consequence.** About $35/month fixed
cost even in dev. Cheaper alternative if that matters: public IPs on agents with the same NSG.

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

## ADR-6: Snapshots to Blob with the VM's managed identity
**Context.** K3s can only ship snapshots to S3-compatible storage; Azure Blob is not.
**Decision.** K3s snapshots locally; a systemd timer uploads with `curl` and an identity token from
the instance metadata service. **Consequence.** No credentials on disk and no extra software.

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
a reason per check in `infra/.checkov.yaml`: public IP on the ingress node, port 80 open (ACME),
service endpoints + firewall instead of private endpoints, platform-managed encryption keys, LRS
replication. **Consequence.** Each is a conscious prod hardening item, listed in the summary.

## ADR-10: K3s built-ins are kept
**Context.** K3s ships Traefik, ServiceLB, local-path and metrics-server. **Decision.** Disable
nothing: Traefik is the ingress, ServiceLB binds 80/443 on the node (no Azure load balancer needed),
local-path stores PVs on the managed data disk (`/mnt/data`), metrics-server feeds the HPA.
**Consequence.** PVs are node-local: a pod with a volume is tied to its node.

## ADR-11: Monitoring runs in-cluster
**Context.** The brief allows node_exporter on the hosts *if* monitoring is external.
**Decision.** kube-prometheus-stack in the cluster, which already deploys node-exporter as a
DaemonSet; there is therefore no `monitoring_agents` Ansible role. Loki runs as a single binary on
local disk; Alloy (not the deprecated Promtail) ships logs. **Consequence.** If the cluster is
down, so is its monitoring - Azure Monitor integration is the listed next step.

## ADR-12: Images are built by CI, not on the cluster
**Context.** The brief asks for a Docker role for a build/management node. **Decision.** The role
exists and targets the `build` inventory group, which is empty by default; GitHub runners build the
image. K3s nodes run containerd only. **Consequence.** Add a host to `build` to get a build box.
