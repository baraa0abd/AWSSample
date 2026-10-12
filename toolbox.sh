#!/usr/bin/env bash
# Runs a command in the toolbox container with this repo mounted, e.g.
#   ./toolbox.sh make plan ENV=dev
#   ./toolbox.sh kubectl get nodes
# AWS access: sign in on the host first (`aws login`); the session's temporary credentials are
# handed to the container as environment variables. Your SSH and age keys are mounted from the host.
set -euo pipefail
cd "$(dirname "$0")"

docker build -q -t infra-toolbox -f toolbox/Dockerfile ansible/ >/dev/null
mkdir -p "$HOME/.config/sops/age" "$HOME/.ssh" "$HOME/.aws"

# Temporary credentials only; they are never written to disk or printed.
creds=()
if command -v aws >/dev/null && exported=$(aws configure export-credentials --format env-no-export 2>/dev/null); then
  # tr: aws.exe on Windows ends lines with CRLF, and a stray CR corrupts the credential.
  while IFS= read -r line; do
    [ -n "$line" ] && creds+=(-e "$line")
  done < <(printf '%s\n' "$exported" | tr -d '\r')
fi

tty=()
[ -t 0 ] && tty=(-it)
# pwd -W / MSYS_NO_PATHCONV: hand Docker real Windows paths when run from Git Bash.
host_path() { (cd "$1" && (pwd -W 2>/dev/null || pwd)); }
# TOOLBOX_NETWORK joins another container's network (used by the local sample to reach K3s).
net=()
[ -n "${TOOLBOX_NETWORK:-}" ] && net=(--network "$TOOLBOX_NETWORK")
MSYS_NO_PATHCONV=1 docker run --rm "${tty[@]}" "${creds[@]}" "${net[@]}" -e ENV="${ENV:-dev}" \
  -v "$(host_path .):/repo" \
  -v infra-toolbox-home:/root \
  -v "$(host_path "$HOME/.ssh"):/ssh-host:ro" \
  -v "$(host_path "$HOME/.aws"):/root/.aws:ro" \
  -v "$(host_path "$HOME/.config/sops/age"):/root/.config/sops/age" \
  -e KUBECONFIG="/repo/.kube/${ENV:-dev}.yaml" \
  infra-toolbox "$@"
