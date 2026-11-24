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

## Migrate from CT 100

Goddard was an unprivileged Debian container (CT 100). Its root volume,
`local-lvm:vm-100-disk-0`, holds the chain, Fulcrum and LND data and becomes the VM's
data disk without copying anything.

LND must never run in two places, and an old copy of its data must never start.
Either broadcasts revoked channel states and the peers can take the channel
balances. Follow the order below.

Clients keep the same address and ports. The firewall accepts LND gRPC (10009)
from aden, the LAN and the phone's tailnet address, and Fulcrum SSL (50002) from
the LAN and the laptop's tailnet address. bitcoind RPC stays local. LND's
macaroons carry over with its data, but its TLS certificate is new, so its
clients need the new one.

1. On CT 100, check `bitcoind --version`, `lncli version` and `Fulcrum --version`.
   None may be newer than what bitcoinix ships, since LND and Fulcrum can't
   downgrade their databases. Fulcrum makes
   bitcoinix enable `txindex`, about 8% of the `blocks` size if
   `/data/bitcoin/indexes/txindex` doesn't exist yet. Grow the volume to fit,
   with headroom for chain growth, and watch the thin pool:
   `pct resize 100 rootfs +300G`.
2. Copy these off the host, for example to the laptop and the NAS: the LND seed,
   the wallet password (`/data/lnd/pwd.txt`), and
   `/data/lnd/data/chain/bitcoin/mainnet/channel.backup`.
3. Stop and disable LND, Fulcrum and bitcoind on CT 100, then
   `pct set 100 --onboot 0 && pct stop 100`.
4. Run `tofu apply` in `opentofu/rune`. VM 110 boots the NixOS ISO.
5. Move the volume to VM 110 on rune. Remove the `rootfs:` line from
   `/etc/pve/lxc/100.conf` so CT 100 can no longer start:
   ```sh
   lvrename pve/vm-100-disk-0 pve/vm-110-disk-9
   qm set 110 --scsi1 local-lvm:vm-110-disk-9,discard=on,ssd=1
   ```
6. VLAN 4 has no DHCP, and the console can't paste. In the VM console, type:
   ```sh
   sudo passwd root
   sudo ip a add 192.168.4.11/24 dev ens18
   sudo ip r add default via 192.168.4.1
   ```
   Then `ssh-keygen -R 192.168.4.11 && ssh root@192.168.4.11` from the laptop.
   Check that `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1` is the
   data disk. disko formats only `drive-scsi0`. Then lay out the data disk:
   ```sh
   mount /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1 /mnt
   mv /mnt/data/bitcoin /mnt/bitcoind
   mv /mnt/data/fulcrum/fulcrum_db /mnt/fulcrum
   mv /mnt/data/lnd/data /mnt/lnd
   umount /mnt
   ```
7. From the laptop, in the repository root:
   ```sh
   nix run github:nix-community/nixos-anywhere -- --flake .#goddard root@192.168.4.11
   ```
   The VM reboots as goddard on 192.168.4.11. bitcoind, Fulcrum and LND fail until the
   next step, because the files still carry the container's owners. The host
   key changes again, so run `ssh-keygen -R 192.168.4.11` before logging in.
8. On goddard:
   ```sh
   chown -R bitcoin:bitcoin /data/bitcoind
   chown -R fulcrum:fulcrum /data/fulcrum
   chown -R lnd:lnd /data/lnd
   install -m 600 /data/data/lnd/pwd.txt /etc/nix-bitcoin-secrets/lnd-wallet-password
   install -m 600 /data/data/fulcrum/cert.pem /etc/nix-bitcoin-secrets/fulcrum-ssl-cert
   install -m 600 /data/data/fulcrum/key.pem /etc/nix-bitcoin-secrets/fulcrum-ssl-key
   systemctl restart setup-secrets bitcoind fulcrum lnd
   lncli getinfo
   ```
   Check that the node pubkey and channels match the old node, and that
   `/mnt/lnd-backup/channel.backup` appears on the NAS. Give aden's
   clients `/etc/nix-bitcoin-secrets/lnd-cert` in place of the old `tls.cert`.
9. Back up `/etc/nix-bitcoin-secrets`. Once the node is in sync, delete the
   leftover Debian files from `/data` and remove CT 100 with `pct destroy 100`.

Up to step 7, you can roll back: on the data disk, move `bitcoind`,
`fulcrum` and `lnd` back to `data/bitcoin`, `data/fulcrum/fulcrum_db` and
`data/lnd/data`, then rename the volume back to `vm-100-disk-0`, restore
`rootfs:` and re-enable the services on CT 100. Once LND has started in the VM,
don't go back.

LND starts only if `/data/lnd/chain/bitcoin/mainnet/wallet.db` exists. Otherwise
bitcoinix would create a new wallet next to the migrated data.

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

### Replace the heine container

The VM takes the container's name and address, so the two never run at once.

1. In Forgejo, create a runner registration token in the same scope as the
   old runner.
2. Create VM 112 with the ISO attached (see
   [`opentofu/dion`](../opentofu/dion/README.md#nixos-heine-vm)).
3. Stop the container and keep it from starting:
   `pct set <ctid> --onboot 0 && pct stop <ctid>`.
4. VLAN 4 has no DHCP. In the VM console:
   ```sh
   sudo passwd root
   sudo ip a add 192.168.4.16/24 dev ens18
   sudo ip r add default via 192.168.4.1
   ```
5. From the laptop, in the repository root:
   ```sh
   ssh-keygen -R 192.168.4.16
   nix run github:nix-community/nixos-anywhere -- --flake .#heine root@192.168.4.16
   ```
6. On heine, after `ssh-keygen -R 192.168.4.16`:
   ```sh
   install -d -m 700 /etc/forgejo-runner
   install -m 600 /dev/null /etc/forgejo-runner/token
   nano /etc/forgejo-runner/token
   systemctl restart gitea-runner-heine gitea-runner-build
   ```
7. Check that `heine` and `heine-build` show as online in Forgejo, then run
   the netcup snapshot and the reviewer's `build` workflow by hand. Check
   that Prometheus shows the `heine` target as up. Delete the old runner in
   Forgejo, then the container with `pct destroy <ctid>`.

Until step 7, you can roll back: stop VM 112 and start the container.
