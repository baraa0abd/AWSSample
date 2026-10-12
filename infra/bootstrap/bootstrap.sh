#!/usr/bin/env bash
# Creates the remote-state storage account (once per subscription) and writes backend.hcl
# for every environment. Idempotent. Requires: az login, Owner or User Access Administrator.
set -euo pipefail

PROJECT="${PROJECT:?set PROJECT}"
LOCATION="${LOCATION:?set LOCATION}"

sub_id=$(az account show --query id -o tsv)
rg="${PROJECT}-tfstate-rg"
# Storage account names are global: derive a stable suffix from the subscription.
account="$(echo "${PROJECT}" | tr -d '-' | cut -c1-12)tfstate$(echo -n "$sub_id" | sha1sum | cut -c1-5)"
container="tfstate"

az group create -n "$rg" -l "$LOCATION" --tags project="$PROJECT" managed_by=bootstrap -o none
az storage account create -n "$account" -g "$rg" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 --https-only true \
  --allow-blob-public-access false --allow-shared-key-access false -o none
# State history: recover from a bad apply or an accidental delete.
az storage account blob-service-properties update --account-name "$account" -g "$rg" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 30 -o none
az storage container-rm create --storage-account "$account" -g "$rg" -n "$container" -o none

# Shared keys are disabled, so whoever runs tofu needs a data-plane role.
scope=$(az storage account show -n "$account" -g "$rg" --query id -o tsv)
me=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee-object-id "$me" --assignee-principal-type User \
  --role "Storage Blob Data Contributor" --scope "$scope" -o none

for env_dir in "$(dirname "$0")"/../environments/*/; do
  cat > "${env_dir}backend.hcl" <<HCL
resource_group_name  = "$rg"
storage_account_name = "$account"
container_name       = "$container"
HCL
done

echo "State backend ready: $account/$container (backend.hcl written; the role assignment can take ~1 min to propagate)"
