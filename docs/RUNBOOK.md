# Runbook

All commands run from the repository root. `ENV` defaults to `dev`; add `ENV=prod` for production.
On a machine without the tools (Windows), prefix with `./toolbox.sh`, e.g. `./toolbox.sh make plan`.

`export KUBECONFIG=$PWD/.kube/dev.yaml` before using `kubectl`/`helm` by hand.

## First deployment, end to end

```bash
cp local.mk.example local.mk          # fill in project, region, admin user, your IP, image repo
az login                               # ./toolbox.sh az login --use-device-code
make bootstrap                         # once per subscription: remote state
make plan && make apply                # ~5 min: VNet, NSG, VMs, disks, storage
make configure                         # ~10 min: hardening, disks, K3s; writes .kube/dev.yaml
kubectl get nodes                      # all Ready
make secrets                           # age key + encrypted secrets (commit secrets/ and .sops.yaml)
make monitoring                        # Prometheus, Grafana, Loki, Alloy
PUSH=1 make build                      # needs `docker login ghcr.io`
make deploy
curl http://$(tofu -chdir=infra/environments/dev output -json stack | jq -r .server_public_ip)/
```

To serve HTTPS, set `DOMAIN` (your own name, or the `server_fqdn` printed by `make output`) and
`ACME_EMAIL` in `local.mk`, then `make deploy` again.

## Deploy a new version

Merge to `main`: CI builds, scans, pushes, deploys to dev and waits for approval before prod.
By hand:

```bash
PUSH=1 make build && make deploy                 # current commit
make deploy IMAGE_TAG=<git-sha> ENV=prod         # a specific, already-built image
```

`helm --atomic` rolls a failed rollout back on its own; the command exits non-zero.

## Roll back

```bash
helm -n webapp-dev history webapp
helm -n webapp-dev rollback webapp <REVISION> --wait
kubectl -n webapp-dev rollout status deployment/webapp
```

Infrastructure: revert the commit and `make plan && make apply`. If state itself is damaged,
restore an earlier blob version of `<env>.tfstate` in the tfstate storage account (versioning is on).

## Scale

```bash
# Pods: edit autoscaling.minReplicas / maxReplicas in k8s/chart/values-<env>.yaml, then
make deploy

# Nodes: edit agent_count in infra/environments/<env>/terraform.tfvars, then
make plan && make apply && make configure        # new agents join; existing nodes report no change

# Remove a node: drain first, then lower agent_count (the highest-numbered agent is removed)
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <node>
make plan && make apply
```

Upgrade K3s: change `k3s_version` in `ansible/group_vars/all.yml`, then `make configure`.
The server is upgraded first, then the agents.

## Observability

```bash
kubectl -n monitoring port-forward svc/kps-grafana 3000:80           # http://localhost:3000, user admin
sops decrypt secrets/dev/monitoring.enc.yaml                          # the admin password
kubectl -n monitoring port-forward svc/kps-prometheus 9090:9090      # Status -> Targets: all UP
kubectl -n monitoring port-forward svc/kps-alertmanager 9093:9093
```

Logs: Grafana -> Explore -> Loki -> `{namespace="webapp-dev"}`, or the *Logs / Explorer* dashboard.

Fire a test alert (the app's `/fail` endpoint always returns 500; `AppHigh5xxRate` fires after ~5 min):

```bash
while true; do curl -s -o /dev/null http://<server-ip>/fail; sleep 0.2; done
```

The always-firing `Watchdog` alert in Alertmanager proves the alerting pipeline itself is alive.

## Rotate secrets

```bash
# Application secret or Grafana password
sops secrets/dev/app.enc.yaml            # opens $EDITOR on the decrypted content
make deploy                              # pods restart automatically (config checksum changes)
sops secrets/dev/monitoring.enc.yaml && make monitoring

# age key (e.g. someone left the team)
age-keygen -o ~/.config/sops/age/keys.txt.new    # put the new public key in .sops.yaml
sops updatekeys secrets/dev/*.enc.yaml           # with the old key still in place
# then replace keys.txt with the new key, and update the SOPS_AGE_KEY secret in GitHub

# K3s join token
ssh <admin>@<server-ip> sudo k3s token rotate    # then: make configure

# SSH key: replace ~/.ssh/id_ed25519*, then make plan && make apply
#   NOTE: Azure only applies admin_ssh_key at VM creation - this REPLACES the VMs.
#   To rotate without rebuilding, add the new key to ~/.ssh/authorized_keys on each node instead.

# Registry pull token: update the GHCR_PULL_TOKEN environment secret and re-run the deploy job
```

## Back up and restore the cluster

Snapshots are automatic: K3s writes one every 6 h to
`/var/lib/rancher/k3s/server/db/snapshots`, and `k3s-backup.timer` copies them hourly to the
`k3s-snapshots` container of the backup storage account (kept 30 days).

```bash
ssh <admin>@<server-ip>
sudo k3s etcd-snapshot save --name before-change      # on-demand snapshot
sudo systemctl start k3s-backup.service               # upload now
sudo journalctl -u k3s-backup.service -n 20           # verify
```

Restore onto the server (same VM, or a freshly provisioned and configured one):

```bash
# 1. If the snapshot is not on the disk any more, download it (from an allowed admin IP)
az storage blob download --auth-mode login --account-name <backup-account> \
  -c k3s-snapshots -n <server-hostname>/<snapshot-file> -f snapshot.db
scp snapshot.db <admin>@<server-ip>:/tmp/

# 2. On the server
sudo systemctl stop k3s
sudo k3s server --cluster-reset --cluster-reset-restore-path=/tmp/snapshot.db
sudo systemctl start k3s

# 3. On every agent
sudo systemctl restart k3s-agent
```

Etcd snapshots contain Kubernetes objects, not volume data. Prometheus and Loki data live on the
nodes' managed disks; snapshot those disks in Azure if that history matters.

## Start dev again after the nightly shutdown

```bash
az vm start --ids $(az vm list -g <project>-dev-rg --query "[].id" -o tsv)
kubectl get nodes        # Ready again after about a minute
```

## Your IP changed and you are locked out

Update `ADMIN_CIDRS` in `local.mk`, then `make plan && make apply`. That updates the NSG and the
storage firewalls; nothing on the nodes depends on your IP. Better: use a stable CIDR (office or VPN).

## Rebuilt a VM and SSH refuses the host key

```bash
ssh-keygen -R <ip>
```

## Destroy

```bash
make destroy ENV=dev            # asks for confirmation; removes every resource of the environment
```

The remote-state resource group (`<project>-tfstate-rg`) is deliberately not managed by tofu.
Delete it by hand only when no environment is left: `az group delete -n <project>-tfstate-rg`.

## Verification status

Tested locally (no cloud needed): `tofu fmt`/`validate`, tflint, checkov, yamllint, ansible-lint,
playbook syntax check, image build + run + Trivy scan, `helm lint`/`template`, kubeconform, and
rendering of all three monitoring charts with this repo's values.
Not yet run against a real subscription: every command above that touches Azure or a live cluster.
Run through "First deployment" once in dev and correct this section.
