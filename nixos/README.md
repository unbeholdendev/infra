# NixOS hosts

`goddard` runs Bitcoin Core, LND and Fulcrum with [bitcoinix](https://github.com/bitcoinix/bitcoinix),
pinned in `flake.nix` to a release tag. The root `flake.lock` pins the exact commit.

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
aden, the LAN and the laptop's tailnet address. bitcoind RPC stays local. LND's
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
