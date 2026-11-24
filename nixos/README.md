# NixOS hosts

`goddard` runs Bitcoin Core, LND, Fulcrum, Unbeholden Wallet and Unbeholden LNURL with [bitcoinix](https://github.com/bitcoinix/bitcoinix),
pinned in `flake.nix` to a release tag. The root `flake.lock` pins the exact commit.

`heine` runs the Forgejo Actions runner. See [heine](#heine). It stays on NixOS 26.05
through its own `nixpkgs-stable` input, because unstable drops
`services.gitea-actions-runner`.

`vm.nix` holds what both share: disk layout, boot, SSH and the guest agent.

## Update bitcoinix

Check the new tag's signature against the maintainers' keys:

```sh
git clone https://github.com/bitcoinix/bitcoinix && cd bitcoinix
git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile=helper/release-keys/ssh-allowed-signers verify-tag vX.Y.Z
git rev-list -n1 vX.Y.Z
```

Renovate opens a PR that sets the new tag in `flake.nix` but cannot update
`flake.lock`. On that branch, run `nix flake lock`, check that the locked
`bitcoinix` rev matches, and push. Follow
[upgrading.md](https://github.com/bitcoinix/bitcoinix/blob/master/docs/upgrading.md)
for every version you skip, then set `nix-bitcoin.configVersion`.

## Deploy

From the repository root:

```sh
nixos-rebuild switch --flake .#goddard --target-host root@192.168.4.11
```

`generateSecrets` keeps the secrets in `/etc/nix-bitcoin-secrets` on goddard.
They are not in Git. Back them up off the host.

## Channel backups

Each change to LND's `channel.backup` is copied to TrueNAS at
`/mnt/storage/lnd-backups`. A timer repeats the copy 5 minutes after boot and
hourly, so a missed change or an unreachable NAS catches up. Before the first deploy, create that dataset and an
NFS share for 192.168.4.11 with maproot root, and add a router rule
`goddard_nfs`: 192.168.4.11 → 192.168.5.2 tcp/2049. The file is encrypted with
the LND seed. Restoring from it closes all channels and returns their funds
on-chain.

## LND wallet

LND starts only if `/data/lnd/chain/bitcoin/mainnet/wallet.db` exists.
Clients use `/etc/nix-bitcoin-secrets/lnd-cert` to verify the gRPC connection.

## heine

heine runs two runners, both on `catthehacker/ubuntu:act-latest`:

- `heine` serves `docker`, for checks and pull requests. It runs up to three
  jobs at once. Jobs get no Docker socket.
- `heine-build` serves `docker-build`, one job at a time, since its jobs share
  the host's Docker daemon. Jobs get the host's Docker socket
  (`docker_host: automount`), which buildx's `docker` driver needs, so they
  are root on heine. Use it only for workflows that run trusted code, such as
  a manual build from `main`, never on `pull_request`.

Each runner serves the actions cache through a proxy on heine's own address:
`heine` on 8088, `heine-build` on 8089. Job containers reach it from their
Docker bridge, so the firewall accepts those ports on `br-+` only, not from the
LAN. If a job's cache steps hang until a timeout, check that rule first. The
firewall otherwise admits SSH, and the node exporter (9100) from the worker.

Both read the registration token from `/etc/forgejo-runner/token` as
`TOKEN=<token>`, mode 600, not in Git. Each registers on first start, and again
when the token or labels change.

Deploy changes from the repository root:

```sh
nixos-rebuild switch --flake .#heine --target-host root@192.168.4.16
```
