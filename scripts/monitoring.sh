#!/usr/bin/env bash
# Installs the observability stack into the `monitoring` namespace: kube-prometheus-stack
# (Prometheus, Alertmanager, Grafana), Loki, Alloy, dashboards and alert rules.
# Usage: ENV=dev scripts/monitoring.sh
source "$(dirname "$0")/lib.sh"

KPS_VERSION=92.3.0
LOKI_VERSION=7.3.0
ALLOY_VERSION=1.13.1
ns=monitoring
v=monitoring/values

# Loki first so Alloy and the Grafana datasource have something to talk to.
helm upgrade --install loki loki --repo https://grafana.github.io/helm-charts --version "$LOKI_VERSION" \
  -n "$ns" --create-namespace -f "$v/loki.yaml" -f "$v/loki.${ENV}.yaml" --wait --timeout 10m

monitoring_secrets=$(decrypt_secrets monitoring)
# The Grafana admin password comes from the SOPS-encrypted file; the chart stores it in a Secret.
helm upgrade --install kps kube-prometheus-stack --repo https://prometheus-community.github.io/helm-charts \
  --version "$KPS_VERSION" -n "$ns" -f "$v/kube-prometheus-stack.yaml" -f "$v/kube-prometheus-stack.${ENV}.yaml" \
  -f "$monitoring_secrets" --wait --timeout 15m

helm upgrade --install alloy alloy --repo https://grafana.github.io/helm-charts --version "$ALLOY_VERSION" \
  -n "$ns" -f "$v/alloy.yaml" --wait --timeout 5m

# Dashboards as code: the Grafana sidecar loads every ConfigMap labelled grafana_dashboard.
kubectl -n "$ns" create configmap custom-dashboards --from-file=monitoring/dashboards \
  --dry-run=client -o yaml | kubectl label --local -f - grafana_dashboard=1 -o yaml | kubectl apply --server-side -f -
kubectl -n "$ns" apply -f monitoring/alerts/

kubectl -n "$ns" get pods
echo "Grafana: kubectl -n $ns port-forward svc/kps-grafana 3000:80   (user: admin, password: sops decrypt secrets/${ENV}/monitoring.enc.yaml)"
