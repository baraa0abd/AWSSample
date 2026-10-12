#!/usr/bin/env bash
# Local sample of the whole flow on Docker - no cloud account. Run on the host (needs docker + tofu):
#   scripts/local.sh up       provision (OpenTofu) -> configure (Ansible) -> build -> monitoring -> deploy
#   scripts/local.sh status   nodes, pods, URLs
#   scripts/local.sh down     destroy everything again
set -euo pipefail
cd "$(dirname "$0")/.."

TF="tofu -chdir=infra/environments/local"
SERVER=k3s-local-server-0
IMAGE=webapp
TAG=$(git rev-parse --short=12 HEAD)
export ENV=local MSYS_NO_PATHCONV=1

# Everything that talks to the cluster runs in the toolbox, inside the server's network namespace,
# so the kubeconfig K3s wrote (https://127.0.0.1:6443) works unchanged.
tb() { TOOLBOX_NETWORK="container:$SERVER" ./toolbox.sh "$@"; }

urls() {
  cat <<EOF

  App           http://localhost:8080         (http://localhost:8080/fail returns 500, for the alert)
  Grafana       http://localhost:3000         user: admin   password: scripts/local.sh password
  Prometheus    http://localhost:9090         Status -> Targets, Alerts
  Alertmanager  http://localhost:9093
EOF
}

case "${1:-}" in
  up)
    echo "== 1/6 provision: OpenTofu creates the K3s node containers"
    mkdir -p .kube
    $TF init -input=false >/dev/null
    $TF apply -input=false -auto-approve

    echo "== 2/6 configure: Ansible waits for the cluster and labels the nodes"
    tb sh -c 'cd ansible && ansible-playbook -i inventories/local/hosts.yml local.yml'

    echo "== 3/6 build: image built, scanned, and loaded onto every node (no registry needed locally)"
    IMAGE_REPO=$IMAGE IMAGE_TAG=$TAG bash scripts/build.sh
    for node in $($TF output -json nodes | tr -d '[]"\r\n' | tr ',' ' '); do
      docker save "$IMAGE:$TAG" | docker exec -i "$node" ctr -n k8s.io images import - >/dev/null
    done

    echo "== 4/6 secrets: age key + SOPS-encrypted values"
    tb bash scripts/secrets-init.sh

    echo "== 5/6 observe: Prometheus, Alertmanager, Grafana, Loki, Alloy"
    tb bash scripts/monitoring.sh

    echo "== 6/6 deploy: the app chart"
    tb env IMAGE_REPO=$IMAGE IMAGE_TAG="$TAG" bash scripts/deploy.sh

    # Publish the UIs: port-forwards listen inside the server container, whose ports tofu
    # mapped to localhost.
    docker rm -f k3s-local-ui >/dev/null 2>&1 || true
    docker run -d --name k3s-local-ui --restart unless-stopped --network "container:$SERVER" \
      -v "$(pwd -W 2>/dev/null || pwd)/.kube:/kube:ro" -e KUBECONFIG=/kube/local.yaml infra-toolbox sh -c '
        kubectl -n monitoring port-forward --address 0.0.0.0 svc/kps-grafana 3000:80 &
        kubectl -n monitoring port-forward --address 0.0.0.0 svc/kps-prometheus 9090:9090 &
        kubectl -n monitoring port-forward --address 0.0.0.0 svc/kps-alertmanager 9093:9093 &
        wait' >/dev/null
    echo "== ready"
    urls
    ;;
  status)
    tb sh -c 'kubectl get nodes; echo; kubectl get pods -A | grep -v kube-system'
    urls
    ;;
  password)
    tb sh -c 'sops decrypt secrets/local/monitoring.enc.yaml | sed -n "s/.*adminPassword: //p"'
    ;;
  down)
    docker rm -f k3s-local-ui >/dev/null 2>&1 || true
    $TF destroy -input=false -auto-approve
    ;;
  *)
    echo "usage: scripts/local.sh up|status|password|down" >&2
    exit 1
    ;;
esac
