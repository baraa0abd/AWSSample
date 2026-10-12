#!/usr/bin/env bash
# Deploys the app chart to <APP_NAME>-<ENV>. A failed rollout is rolled back automatically.
# Usage: ENV=dev IMAGE_REPO=ghcr.io/<owner>/webapp [IMAGE_TAG=<sha>] [DOMAIN=... ACME_EMAIL=...] scripts/deploy.sh
#        Optional REGISTRY_USER / REGISTRY_TOKEN create the image pull secret for a private registry.
source "$(dirname "$0")/lib.sh"

APP_NAME="${APP_NAME:-webapp}"
: "${IMAGE_REPO:?set IMAGE_REPO, e.g. ghcr.io/<owner>/webapp}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short=12 HEAD)}"
DOMAIN="${DOMAIN:-}"
CERT_MANAGER_VERSION=v1.21.2
ns="${APP_NAME}-${ENV}"

kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
# Pod Security Admission: the namespace refuses pods that are not fully locked down.
kubectl label namespace "$ns" pod-security.kubernetes.io/enforce=restricted --overwrite

args=()
if [ -n "${REGISTRY_TOKEN:-}" ]; then
  kubectl -n "$ns" create secret docker-registry registry-credentials \
    --docker-server="${IMAGE_REPO%%/*}" --docker-username="${REGISTRY_USER:?}" --docker-password="$REGISTRY_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
  args+=(--set "imagePullSecrets[0].name=registry-credentials")
fi

if [ -n "$DOMAIN" ]; then
  # TLS only makes sense with a real hostname: install cert-manager and a Let's Encrypt issuer.
  monitor=false
  kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1 && monitor=true
  helm upgrade --install cert-manager cert-manager --repo https://charts.jetstack.io \
    --version "$CERT_MANAGER_VERSION" -n cert-manager --create-namespace \
    --set crds.enabled=true --set prometheus.servicemonitor.enabled="$monitor" --wait
  kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${ACME_EMAIL:?set ACME_EMAIL when DOMAIN is set}
    privateKeySecretRef:
      name: letsencrypt-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik
EOF
  args+=(--set "ingress.host=$DOMAIN" --set ingress.tls=true)
fi

app_secrets=$(decrypt_secrets app) # on its own line so a failure stops the script
# --atomic: wait for the rollout and roll back to the previous release if it does not become healthy.
helm upgrade --install "$APP_NAME" k8s/chart -n "$ns" \
  -f "k8s/chart/values-${ENV}.yaml" -f "$app_secrets" \
  --set image.repository="$IMAGE_REPO" --set image.tag="$IMAGE_TAG" \
  "${args[@]}" --atomic --timeout 5m

kubectl -n "$ns" rollout status "deployment/${APP_NAME}" --timeout=2m
kubectl -n "$ns" get ingress,hpa,pods
