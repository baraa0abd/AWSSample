# Runbook

All commands run from the repository root. `ENV` defaults to `dev`; add `ENV=prod` for production.
On a machine without the tools (Windows), prefix with `./toolbox.sh`, e.g. `./toolbox.sh make plan`.
The toolbox picks up the AWS session of the host (`aws login`).

`export KUBECONFIG=$PWD/.kube/dev.yaml` before using `kubectl`/`helm` by hand.
The SSH user on every node is `ubuntu`.

## First deployment, end to end

```bash
cp local.mk.example local.mk          # project, region, your public IP, image repo
aws login                              # or any other way of getting AWS credentials
make bootstrap                         # once per account: remote-state bucket
make plan && make apply                # ~4 min: VPC, security group, instances, disks, bucket
make configure                         # ~10 min: hardening, disks, K3s; writes .kube/dev.yaml
kubectl get nodes                      # all Ready
make secrets                           # age key + encrypted secrets (commit secrets/ and .sops.yaml)
make monitoring                        # Prometheus, Grafana, Loki, Alloy
PUSH=1 make build                      # needs `docker login ghcr.io`
make deploy
curl http://$(tofu -chdir=infra/environments/dev output -json stack | jq -r .server_public_ip)/
```

To serve HTTPS, point a DNS name you control at the server IP, set `DOMAIN` and `ACME_EMAIL` in
`local.mk`, then `make plan && make apply && make configure` (adds the name to the API
certificate) and `make deploy` again. Let's Encrypt does not issue for AWS's own `amazonaws.com` names.

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
restore an earlier version of `<env>.tfstate` in the tfstate bucket (versioning is on).

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

Fire a test alert (the app's `/fail` endpoint always returns 500; `AppHigh5xxRate` goes pending
within about two minutes and fires after five):

```bash
while true; do curl -s -o /dev/null http://<server-ip>/fail; sleep 0.3; done
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
ssh ubuntu@<server-ip> sudo k3s token rotate     # then: make configure

# SSH key: the EC2 key pair is only read at instance creation, so changing it in tofu does
# nothing for running nodes. Add the new public key to ~/.ssh/authorized_keys on each node
# and remove the old one.

# Registry pull token: update the GHCR_PULL_TOKEN environment secret and re-run the deploy job
```

## Back up and restore the cluster

Snapshots are automatic: every 6 h K3s writes one to `/var/lib/rancher/k3s/server/db/snapshots`
and uploads it to `s3://<project>-<env>-k3s-backup-<account-id>/<server-name>/` (kept 30 days).

```bash
ssh ubuntu@<server-ip>
sudo k3s etcd-snapshot save --name before-change      # on-demand snapshot, also uploaded
sudo k3s etcd-snapshot ls                              # local and S3 copies
```

Restore onto the server (same instance, or a freshly provisioned and configured one):

```bash
# On the server. K3s downloads the snapshot from S3 itself (it reads the S3 settings from its config).
sudo systemctl stop k3s
sudo k3s server --cluster-reset --cluster-reset-restore-path=<snapshot-file-name>
sudo systemctl start k3s

# On every agent
sudo systemctl restart k3s-agent
```

Etcd snapshots contain Kubernetes objects, not volume data. Prometheus and Loki data live on the
nodes' EBS data disks; take EBS snapshots if that history matters.

## Start dev again after the nightly shutdown

```bash
aws ec2 start-instances --instance-ids $(aws ec2 describe-instances \
  --filters "Name=tag:project,Values=<project>" "Name=tag:environment,Values=dev" \
            "Name=instance-state-name,Values=stopped" \
  --query "Reservations[].Instances[].InstanceId" --output text)
kubectl get nodes        # Ready again after about a minute
```

## Your IP changed and you are locked out

Update `ADMIN_CIDRS` in `local.mk`, then `make plan && make apply`. That updates the security
group; nothing on the nodes depends on your IP. Better: use a stable CIDR (office or VPN).

## Rebuilt an instance and SSH refuses the host key

```bash
ssh-keygen -R <ip>
```

## Destroy

```bash
make destroy ENV=dev            # asks for confirmation; removes every resource of the environment
```

In dev the backup bucket is emptied and deleted with it; in prod a non-empty bucket blocks the
destroy on purpose. The remote-state bucket (`<project>-tfstate-<account-id>`) is deliberately not
managed by tofu: empty and delete it by hand only when no environment is left.

## Verification status

Tested locally (no cloud needed): `tofu fmt`/`validate`, tflint, checkov, yamllint, ansible-lint,
playbook syntax check, image build + run + Trivy scan, `helm lint`/`template`, kubeconform; and
`scripts/monitoring.sh` + `scripts/deploy.sh` against a local K3s of the production version
(ingress, HPA, network policy, metrics, logs, dashboards, alert, automatic rollback).
Not yet run against a real AWS account: every command above that touches AWS or the real nodes.
Run through "First deployment" once in dev and correct this section.
