# infraAzure

Production-style infrastructure and delivery on Azure, entirely as code:

**OpenTofu** provisions VMs -> **Ansible** builds a K3s cluster -> **Docker** builds a scanned image
-> **Helm** deploys it with ingress, autoscaling and network policies -> **Prometheus, Grafana,
Loki and Alloy** observe it -> **GitHub Actions** automates it with OIDC (no stored cloud secrets).

- Design: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and decisions in [docs/ADR.md](docs/ADR.md)
- Operations: [docs/RUNBOOK.md](docs/RUNBOOK.md)

## Quick start

```bash
cp local.mk.example local.mk     # project name, region, admin user, your public IP, image repo
az login
make bootstrap                   # remote state (once)
make plan && make apply          # infrastructure  (billable)
make configure                   # K3s cluster
make secrets && make monitoring  # encrypted secrets, observability stack
PUSH=1 make build && make deploy # the app
```

`make help` lists every target. No tools installed, or on Windows? Everything except `build` runs
in a container with pinned versions: `./toolbox.sh make plan`.

Prerequisites when running natively: OpenTofu >= 1.6 (or Terraform), Azure CLI, Ansible
(`pip install -r ansible/requirements.txt && ansible-galaxy collection install -r ansible/requirements.yml`),
Docker, kubectl, Helm 3, sops, age, make, jq. An SSH key at `~/.ssh/id_ed25519`.

## Layout

| Path | What |
|---|---|
| `infra/` | OpenTofu modules, `dev`/`prod` environments, state bootstrap, OIDC bootstrap |
| `ansible/` | Roles (`common`, `disks`, `docker`, `k3s_server`, `k3s_agent`) and `site.yml` |
| `app/` | Go service and its Dockerfile |
| `k8s/chart/` | Helm chart for the app |
| `monitoring/` | Helm values, dashboards (JSON) and alert rules |
| `scripts/` | build, deploy, monitoring and secrets scripts called by the Makefile |
| `secrets/` | SOPS-encrypted secrets only (`*.enc.yaml`) |
| `.github/workflows/` | `infra`, `config`, `app` pipelines and the reusable `deploy` |
| `toolbox/`, `toolbox.sh` | Container with every CLI at a pinned version |
| `docs/` | Architecture, ADRs, runbook |

## Conventions

- Names: `<project>-<env>-<resource>`. Environments: `dev`, `prod`.
- Every version is pinned: providers (lock file), K3s, Helm charts, images (digest), Ansible
  collections, GitHub Actions (commit SHA), CLI tools.
- No secrets in git: SOPS + age. No cloud credentials in CI: OIDC.
- Images are deployed by git SHA; `latest` is rejected by the chart.

## CI setup (once)

1. `PROJECT=<project> GITHUB_REPO=<owner>/<repo> bash infra/bootstrap/oidc.sh` and set the three
   printed values as repository **variables**.
2. More repository variables: `PROJECT`, `LOCATION`, `ADMIN_USER`, `ADMIN_CIDRS` (HCL list),
   `SSH_PUBLIC_KEY`, `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT` (both printed by `make bootstrap`).
3. Create GitHub environments `dev` and `prod`; add **required reviewers** (that is the manual
   approval for `tofu apply` and for production deploys).
4. Per environment, secrets `KUBECONFIG_B64` (`base64 -w0 .kube/<env>.yaml`), `SOPS_AGE_KEY` (content
   of the age key file), `GHCR_PULL_TOKEN` (PAT with `read:packages`); optional variables `DOMAIN`,
   `ACME_EMAIL`.
