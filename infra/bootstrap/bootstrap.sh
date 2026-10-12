#!/usr/bin/env bash
# Creates the remote-state S3 bucket (once per account) and writes backend.hcl for every
# environment. Idempotent. Requires AWS credentials (`aws login`).
set -euo pipefail

PROJECT="${PROJECT:?set PROJECT}"
REGION="${REGION:?set REGION}"

account_id=$(aws sts get-caller-identity --query Account --output text)
bucket="${PROJECT}-tfstate-${account_id}" # bucket names are global: the account ID makes it unique

if ! aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
  if [ "$REGION" = "us-east-1" ]; then # us-east-1 rejects an explicit LocationConstraint
    aws s3api create-bucket --bucket "$bucket" --region "$REGION"
  else
    aws s3api create-bucket --bucket "$bucket" --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=$REGION"
  fi
fi
aws s3api put-public-access-block --bucket "$bucket" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
# State history: recover from a bad apply or an accidental delete.
aws s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$bucket" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

for env_dir in "$(dirname "$0")"/../environments/*/; do
  cat > "${env_dir}backend.hcl" <<HCL
bucket = "$bucket"
region = "$REGION"
HCL
done

echo "State backend ready: s3://$bucket (backend.hcl written)"
