#!/usr/bin/env bash
# Shared by deploy.sh and monitoring.sh.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

ENV="${ENV:?set ENV to dev or prod}"
export KUBECONFIG="${KUBECONFIG:-$PWD/.kube/${ENV}.yaml}"
[ -f "$KUBECONFIG" ] || { echo "no kubeconfig at $KUBECONFIG - run 'make configure ENV=$ENV' first" >&2; exit 1; }

# Decrypted secrets only ever exist in this private temp dir, removed when the script exits.
SECRETS_TMP=$(mktemp -d)
trap 'rm -rf "$SECRETS_TMP"' EXIT

# Prints the path of a decrypted copy of secrets/<env>/<name>.enc.yaml.
decrypt_secrets() {
  local src="secrets/${ENV}/$1.enc.yaml"
  [ -f "$src" ] || { echo "missing $src - run 'make secrets ENV=$ENV'" >&2; return 1; }
  sops decrypt "$src" > "$SECRETS_TMP/$1.yaml"
  echo "$SECRETS_TMP/$1.yaml"
}
