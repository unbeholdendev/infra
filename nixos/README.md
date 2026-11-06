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

Set the tag in `flake.nix`, run `nix flake lock`, and check that the locked
`bitcoinix` rev matches. Follow
[upgrading.md](https://github.com/bitcoinix/bitcoinix/blob/master/docs/upgrading.md)
for every version you skip, then set `nix-bitcoin.configVersion`.

## Deploy

From the repository root:

```sh
nixos-rebuild switch --flake .#goddard --target-host root@192.168.4.11
```

`generateSecrets` keeps the secrets in `/etc/nix-bitcoin-secrets` on goddard.
They are not in Git. Back them up off the host.

## Migrate from CT 100

Goddard was an unprivileged Debian container (CT 100). Its root volume,
`local-lvm:vm-100-disk-0`, holds the chain, Fulcrum and LND data and becomes the VM's
data disk without copying anything.

LND must never run in two places, and an old copy of its data must never start.
Either broadcasts revoked channel states and the peers can take the channel
balances. Follow the order below.

Clients keep the same address and ports. The firewall accepts LND gRPC (10009)
from aden only, and Fulcrum SSL (50002) from aden, the LAN and the laptop's
tailnet address. bitcoind RPC stays local. LND's macaroons carry over with its
data, but its TLS certificate is new, so aden's clients need the new one.

1. On CT 100, check `bitcoind --version`, `lncli version` and `Fulcrum --version`.
   None may be newer than what bitcoinix ships, since LND and Fulcrum can't
   downgrade their databases. Note where the LND dir (`.lnd`) is. Fulcrum makes
   bitcoinix enable `txindex`, about 8% of the `blocks` size if
   `/data/bitcoin/indexes/txindex` doesn't exist yet. Grow the volume to fit,
   with headroom for chain growth, and watch the thin pool:
   `pct resize 100 rootfs +300G`.
2. Copy these off the host, for example to the laptop and the NAS: the LND seed,
   the wallet password, and `.lnd/data/chain/bitcoin/mainnet/channel.backup`.
3. Stop and disable LND, Fulcrum and bitcoind on CT 100, then
   `pct set 100 --onboot 0 && pct stop 100`.
4. Run `tofu apply` in `opentofu/rune`. VM 110 boots the NixOS ISO.
5. Move the volume to VM 110 on rune. Remove the `rootfs:` line from
   `/etc/pve/lxc/100.conf` so CT 100 can no longer start:
   ```sh
   lvrename pve/vm-100-disk-0 pve/vm-110-disk-9
   qm set 110 --scsi1 local-lvm:vm-110-disk-9,discard=on,ssd=1
   ```
6. In the VM console, set a root password with `passwd` and note the DHCP address.
   Check that `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1` is the
   data disk. disko formats only `drive-scsi0`. Then lay out the data disk:
   ```sh
   mount /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1 /mnt
   mv /mnt/data/bitcoin /mnt/bitcoind
   mv /mnt/data/fulcrum/fulcrum_db /mnt/fulcrum
   mv /mnt/<path>/.lnd/data /mnt/lnd
   umount /mnt
   ```
7. From the laptop, in the repository root:
   ```sh
   nix run github:nix-community/nixos-anywhere -- --flake .#goddard root@<dhcp-address>
   ```
   The VM reboots as goddard on 192.168.4.11. bitcoind, Fulcrum and LND fail until the
   next step, because the files still carry the container's owners.
8. On goddard:
   ```sh
   chown -R bitcoin:bitcoin /data/bitcoind
   chown -R fulcrum:fulcrum /data/fulcrum
   chown -R lnd:lnd /data/lnd
   install -m 600 /dev/stdin /etc/nix-bitcoin-secrets/lnd-wallet-password  # paste the old password, then Ctrl-D
   # Fulcrum's old `cert` and `key` (see the old fulcrum.conf, now under /data), so Electrum clients see the same certificate
   install -m 600 <old-cert> /etc/nix-bitcoin-secrets/fulcrum-ssl-cert
   install -m 600 <old-key> /etc/nix-bitcoin-secrets/fulcrum-ssl-key
   systemctl restart setup-secrets bitcoind fulcrum lnd
   lncli getinfo
   ```
   Check that the node pubkey and channels match the old node. Give aden's
   clients `/etc/nix-bitcoin-secrets/lnd-cert` in place of the old `tls.cert`.
9. Back up `/etc/nix-bitcoin-secrets`. Once the node is in sync, delete the
   leftover Debian files from `/data` and remove CT 100 with `pct destroy 100`.

Up to step 7, you can roll back: on the data disk, move `bitcoind`,
`fulcrum` and `lnd` back to `data/bitcoin`, `data/fulcrum/fulcrum_db` and
`<path>/.lnd/data`, then rename the volume back to `vm-100-disk-0`, restore
`rootfs:` and re-enable the services on CT 100. Once LND has started in the VM,
don't go back.

LND starts only if `/data/lnd/chain/bitcoin/mainnet/wallet.db` exists. Otherwise
bitcoinix would create a new wallet next to the migrated data.
