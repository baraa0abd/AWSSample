# Single entrypoint: provision (OpenTofu) -> configure (Ansible) -> build (Docker) -> deploy (Helm) -> observe.
#   make bootstrap | plan | apply | configure | secrets | monitoring | build | deploy | destroy   [ENV=dev|prod]
# No tools installed (Windows)? Run the same targets through the toolbox: ./toolbox.sh make plan
# (`build` is the exception: it needs the Docker daemon, run scripts/build.sh on the host.)

ENV ?= dev
-include local.mk # your settings; copy local.mk.example

TF      := tofu -chdir=infra/environments/$(ENV)
ANSIBLE := cd ansible && ansible-playbook -i inventories/$(ENV)/hosts.yml site.yml
APP_NAME ?= webapp

# Per-user inputs reach OpenTofu as TF_VAR_*, the scripts as plain environment variables.
export ENV APP_NAME IMAGE_REPO DOMAIN ACME_EMAIL
export AWS_REGION                 = $(REGION)
export TF_VAR_project_name        = $(PROJECT)
export TF_VAR_region              = $(REGION)
export TF_VAR_allowed_admin_cidrs = $(ADMIN_CIDRS)
export TF_VAR_domain              = $(DOMAIN)
export KUBECONFIG                 = $(CURDIR)/.kube/$(ENV).yaml

.PHONY: help bootstrap init plan apply output configure check secrets monitoring build deploy destroy lint

help: ## Show targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'

bootstrap: ## Create the remote-state S3 bucket (once per account)
	PROJECT=$(PROJECT) REGION=$(REGION) bash infra/bootstrap/bootstrap.sh

init:
	$(TF) init -input=false -backend-config=backend.hcl

plan: init ## Plan infrastructure changes -> tfplan
	$(TF) plan -input=false -out=tfplan

apply: ## Apply the saved plan (creates billable AWS resources)
	$(TF) apply -input=false tfplan

output: ## Show infrastructure outputs (IPs, bucket, ...)
	$(TF) output

configure: ## Configure the VMs and bring up K3s; writes .kube/$(ENV).yaml
	$(ANSIBLE)

check: ## Dry-run the configuration and show what would change
	$(ANSIBLE) --check --diff

secrets: ## Create the age key and SOPS-encrypted secrets for ENV (keeps existing ones)
	bash scripts/secrets-init.sh

monitoring: ## Install Prometheus, Alertmanager, Grafana, Loki, Alloy
	bash scripts/monitoring.sh

build: ## Build + Trivy-scan the image (PUSH=1 to push)
	bash scripts/build.sh

deploy: ## Deploy the app chart (IMAGE_TAG defaults to the current git SHA)
	bash scripts/deploy.sh

destroy: init ## Destroy ALL infrastructure of ENV (asks for confirmation)
	$(TF) destroy

lint: ## Static checks that need no cloud access
	tofu fmt -check -recursive infra
	yamllint -s .
	cd ansible && ansible-lint && ansible-playbook site.yml --syntax-check -i localhost,
	helm lint k8s/chart --set image.repository=x --set image.tag=x
