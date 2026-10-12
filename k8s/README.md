# k8s

`chart/` is the Helm chart for the app: Deployment, Service, Ingress (Traefik), HPA, PDB, ConfigMap,
Secret, NetworkPolicies (default deny), ServiceMonitor, optional PVC.

- Deploy: `make deploy` -> `scripts/deploy.sh` (namespace `<app>-<env>`, automatic rollback on failure).
- Per-environment values: `chart/values-<env>.yaml`. Secrets: `secrets/<env>/app.enc.yaml` (SOPS).
- TLS: set `DOMAIN` (a DNS name you control, pointing at the server IP) and `ACME_EMAIL`; the script installs cert-manager and a Let's Encrypt issuer.
- Checks: `helm lint chart ...`, `helm template ... | kubeconform -strict -`.
