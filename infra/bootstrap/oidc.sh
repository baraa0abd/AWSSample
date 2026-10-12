#!/usr/bin/env bash
# Creates the IAM role GitHub Actions assumes through OIDC federation (no access keys exist).
# Idempotent. Requires AWS credentials allowed to manage IAM.
set -euo pipefail

PROJECT="${PROJECT:?set PROJECT}"
GITHUB_REPO="${GITHUB_REPO:?set GITHUB_REPO as owner/repo}"

account_id=$(aws sts get-caller-identity --query Account --output text)
provider_arn="arn:aws:iam::${account_id}:oidc-provider/token.actions.githubusercontent.com"
role="${PROJECT}-github-oidc"

aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$provider_arn" >/dev/null 2>&1 ||
  aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com >/dev/null

# Only this repository may assume the role, and only from the places a workflow runs:
# PR plans, main, and the two gated environments.
trust=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "$provider_arn" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": { "token.actions.githubusercontent.com:sub": [
        "repo:${GITHUB_REPO}:pull_request",
        "repo:${GITHUB_REPO}:ref:refs/heads/main",
        "repo:${GITHUB_REPO}:environment:dev",
        "repo:${GITHUB_REPO}:environment:prod"
      ] }
    }
  }]
}
JSON
)

if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name "$role" --policy-document "$trust"
else
  aws iam create-role --role-name "$role" --assume-role-policy-document "$trust" >/dev/null
fi
# ponytail: AdministratorAccess, because tofu manages IAM roles, VPC, EC2, S3 and Scheduler.
# Replace with a scoped policy (or a permissions boundary) before using this for a real prod account.
aws iam attach-role-policy --role-name "$role" --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

cat <<OUT
Set these as GitHub repository *variables* (identifiers, not secrets):
  AWS_ROLE_ARN=arn:aws:iam::${account_id}:role/${role}
  TFSTATE_BUCKET=${PROJECT}-tfstate-${account_id}
OUT
