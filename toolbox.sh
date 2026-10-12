#!/usr/bin/env bash
# Runs a command in the toolbox container with this repo mounted, e.g.
#   ./toolbox.sh az login --use-device-code
#   ./toolbox.sh make plan ENV=dev
# State that must outlive the container (az login, known_hosts) is kept in the
# `infra-toolbox-home` volume; your SSH and age keys are mounted from the host.
set -euo pipefail
cd "$(dirname "$0")"

docker build -q -t infra-toolbox -f toolbox/Dockerfile ansible/ >/dev/null
mkdir -p "$HOME/.config/sops/age" "$HOME/.ssh"

tty=(); [ -t 0 ] && tty=(-it)
# pwd -W / MSYS_NO_PATHCONV: hand Docker real Windows paths when run from Git Bash.
host_path() { (cd "$1" && (pwd -W 2>/dev/null || pwd)); }
MSYS_NO_PATHCONV=1 docker run --rm "${tty[@]}" \
  -v "$(host_path .):/repo" \
  -v infra-toolbox-home:/root \
  -v "$(host_path "$HOME/.ssh"):/ssh-host:ro" \
  -v "$(host_path "$HOME/.config/sops/age"):/root/.config/sops/age" \
  infra-toolbox "$@"
