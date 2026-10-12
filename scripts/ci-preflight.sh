#!/usr/bin/env bash
# Validate CI inputs without printing credential values or contacting AWS.
set -euo pipefail

case "${1:-}" in
  infra)
    required=(AWS_REGION AWS_ROLE_ARN TFSTATE_BUCKET TF_VAR_project_name
      TF_VAR_region TF_VAR_allowed_admin_cidrs TF_VAR_ssh_public_key)
    ;;
  deploy)
    required=(AWS_REGION AWS_ROLE_ARN PROJECT KUBECONFIG_B64 SOPS_AGE_KEY GHCR_PULL_TOKEN)
    ;;
  *) echo 'usage: ci-preflight.sh infra|deploy' >&2; exit 2 ;;
esac

missing=()
for name in "${required[@]}"; do
  [ -n "${!name:-}" ] || missing+=("$name")
done
if [ "${#missing[@]}" -gt 0 ]; then
  printf '::error::Missing CI setting: %s\n' "${missing[@]}" >&2
  echo 'Configure repository variables and environment secrets as documented in README.md.' >&2
  exit 1
fi

if [ "$1" = deploy ]; then
  for name in app monitoring; do
    if [ ! -f "secrets/${ENV:?set ENV}/$name.enc.yaml" ]; then
      echo "::error::Missing secrets/$ENV/$name.enc.yaml; initialize and commit environment secrets." >&2
      exit 1
    fi
  done
fi
echo 'Required CI settings are present.'
