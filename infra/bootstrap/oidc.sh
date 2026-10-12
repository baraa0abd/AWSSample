#!/usr/bin/env bash
# Creates the Entra app GitHub Actions logs in as, via OIDC federation (no client secret exists).
# Idempotent. Requires: az login with rights to create app registrations and role assignments.
set -euo pipefail

PROJECT="${PROJECT:?set PROJECT}"
GITHUB_REPO="${GITHUB_REPO:?set GITHUB_REPO as owner/repo}"

sub_id=$(az account show --query id -o tsv)
tenant_id=$(az account show --query tenantId -o tsv)
app_name="${PROJECT}-github-oidc"

app_id=$(az ad app list --display-name "$app_name" --query '[0].appId' -o tsv)
[ -n "$app_id" ] || app_id=$(az ad app create --display-name "$app_name" --query appId -o tsv)
az ad sp show --id "$app_id" -o none 2>/dev/null || az ad sp create --id "$app_id" -o none
sp_id=$(az ad sp show --id "$app_id" --query id -o tsv)

# One trust per place a workflow runs: PR plans, main, and the two gated environments.
for subject in pull_request ref:refs/heads/main environment:dev environment:prod; do
  name="github-$(echo "$subject" | tr ':/' '--')"
  az ad app federated-credential show --id "$app_id" --federated-credential-id "$name" -o none 2>/dev/null ||
    az ad app federated-credential create --id "$app_id" -o none --parameters "{
      \"name\": \"$name\",
      \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject\": \"repo:${GITHUB_REPO}:${subject}\",
      \"audiences\": [\"api://AzureADTokenExchange\"]
    }"
done

# Contributor creates resources; User Access Administrator is needed for the one role assignment
# tofu makes (server VM -> backup storage); Blob Data Contributor is for the state itself.
for role in "Contributor" "User Access Administrator" "Storage Blob Data Contributor"; do
  az role assignment create --assignee-object-id "$sp_id" --assignee-principal-type ServicePrincipal \
    --role "$role" --scope "/subscriptions/$sub_id" -o none
done

cat <<OUT
Set these as GitHub repository *variables* (identifiers, not secrets):
  AZURE_CLIENT_ID=$app_id
  AZURE_TENANT_ID=$tenant_id
  AZURE_SUBSCRIPTION_ID=$sub_id
OUT
