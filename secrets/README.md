# secrets

Only SOPS-encrypted files (`<env>/*.enc.yaml`) live here; `.gitignore` blocks everything else.
Create them with `make secrets`, edit with `sops secrets/<env>/<file>.enc.yaml`.
The age private key (`~/.config/sops/age/keys.txt`) is never committed - back it up.
