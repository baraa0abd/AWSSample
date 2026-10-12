# secrets

Only SOPS-encrypted files (`<env>/*.enc.yaml`) live here; `.gitignore` blocks everything else.
Create them with `make secrets`, edit with `sops secrets/<env>/<file>.enc.yaml`.
The age private key (`~/.config/sops/age/keys.txt`) is never committed - back it up.

## First setup on a new machine

The committed local ciphertext requires its original age private key. A newly generated key
cannot decrypt it. Install the original key securely if you have it.

For an independent local sample, preserve the sample files outside the repository and generate
your own recipient and values. Run from the repository root in Bash before `scripts/local.sh up`:

```bash
backup_dir=$(mktemp -d)
mv .sops.yaml secrets/local/app.enc.yaml secrets/local/monitoring.enc.yaml "$backup_dir/"
ENV=local ./toolbox.sh bash scripts/secrets-init.sh
```

This changes the encryption recipient in `.sops.yaml`. Review the regenerated files before
committing; do not replace shared recipients for a local trial. Other existing ciphertext
still needs its original key. Coordinate shared recipient changes and run `sops updatekeys`
with an authorized existing key. Back up your new private key separately from the repository.
