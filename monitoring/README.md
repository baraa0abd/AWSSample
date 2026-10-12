# monitoring

Installed by `make monitoring` (`scripts/monitoring.sh`) into the `monitoring` namespace.

- `values/kube-prometheus-stack*.yaml` - Prometheus, Alertmanager, Grafana (base + per environment).
- `values/loki*.yaml` - Loki single binary, filesystem storage, retention per environment.
- `values/alloy.yaml` - Alloy DaemonSet shipping pod logs to Loki.
- `dashboards/*.json` - loaded by the Grafana sidecar: app RED metrics, logs explorer.
  Node Exporter Full (1860) and K3s (15282) are pulled from grafana.com at pinned revisions;
  Kubernetes cluster dashboards ship with the chart.
- `alerts/*.yaml` - PrometheusRules: node down, disk > 80%, CPU, memory, CrashLoopBackOff, 5xx rate, certificate expiry.

Retention: dev 15 d metrics / 7 d logs, prod 30 d / 30 d. Grafana has no ingress: use `kubectl port-forward` (see the runbook).
Chart versions are pinned at the top of `scripts/monitoring.sh`.
