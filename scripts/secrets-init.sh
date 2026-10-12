#!/usr/bin/env bash
# Creates the SOPS/age setup for one environment: an age key (once), random secrets, encrypted files.
# Existing encrypted files are never overwritten. Usage: ENV=dev scripts/secrets-init.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ENV="${ENV:?set ENV to dev or prod}"
key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

if [ ! -f "$key_file" ]; then
  mkdir -p "$(dirname "$key_file")"
  age-keygen -o "$key_file"
  chmod 600 "$key_file"
  echo "created age key $key_file - BACK IT UP: without it the secrets cannot be decrypted"
fi
recipient=$(age-keygen -y "$key_file")

# Commit .sops.yaml: it only holds the public key and tells sops which files to encrypt for whom.
[ -f .sops.yaml ] || cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: (secrets/.*\.enc\.yaml|\.sops\.ya?ml)\$
    age: $recipient
EOF

random() { head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32; }

mkdir -p "secrets/${ENV}"
encrypt() { # $1 = file name, stdin = plaintext yaml
  local dest="secrets/${ENV}/$1.enc.yaml"
  if [ -f "$dest" ]; then
    echo "keeping existing $dest"
    return
  fi
  sops encrypt --filename-override "$dest" --input-type yaml --output-type yaml /dev/stdin > "$dest"
  echo "wrote $dest"
}

# App chart values: becomes the app's Secret (env vars).
encrypt app <<EOF
secrets:
  API_TOKEN: $(random)
EOF

# kube-prometheus-stack values.
encrypt monitoring <<EOF
grafana:
  adminPassword: $(random)
EOF
