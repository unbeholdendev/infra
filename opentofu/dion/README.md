# Dion VMs

OpenTofu runs on the NixOS laptop and manages only the Proxmox VMs. Talos
configuration, Kubernetes bootstrap, DHCP reservations and application deployment
remain manual. No Talos credentials belong in this directory.

| VM | ID | vCPU | RAM | Disk | MAC |
| --- | --- | --- | --- | --- | --- |
| talos-cp-01 | 100 | 2 | 4 GiB | 20 GiB | 02:00:00:04:01:01 |
| talos-worker-01 | 101 | 4 | 8 GiB | 32 GiB | 02:00:00:04:01:02 |

The VMs use Dion's `local-lvm`, `vmbr0` and VLAN 4. Thin provisioning does not
remove the need to monitor pool usage.

## Access

After merging the dotfiles change, run `dots` on the laptop to install `tofu`.
Run the commands below from this directory.

Use a dedicated Proxmox API token, not root's password. Set
`PROXMOX_VE_API_TOKEN` in the environment to `user@realm!tokenid=secret`, without
putting the value in shell history or this repository. Keep the token in a
private file or password manager. A privilege-separated token needs permissions
on both the user and token.

Scope VM permissions to `/vms/100`, `/vms/101` and `/vms/111`. Scope storage permissions to
`/storage/local-lvm` and `/storage/local`, and network access to
`/sdn/zones/localnetwork/vmbr0`. The VM role needs `VM.Allocate`, `VM.Audit`,
`VM.PowerMgmt` and `VM.Config.CPU`, `VM.Config.Memory`, `VM.Config.Disk`,
`VM.Config.CDROM`, `VM.Config.Network`, `VM.Config.HWType`, `VM.Config.Options`.
Storage needs `Datastore.Audit` and `Datastore.AllocateSpace` on `local-lvm`,
and `Datastore.Audit` on `local`. Network access needs `SDN.Use`.
Check the permissions against the installed Proxmox version before granting;
resolve any additional permission error narrowly rather than assigning an
administrator role. This configuration needs no SSH access.

TLS verification stays enabled. Trust Dion's issuing CA on the laptop, or use
an endpoint with a trusted certificate. For the Proxmox cluster CA, obtain
`/etc/pve/pve-root-ca.pem` through your existing trusted admin connection and
verify its fingerprint before trusting it. The certificate must also cover the
endpoint address. `PROXMOX_VE_INSECURE=true` is a temporary opt-out, not the
default; it disables certificate verification.

## Initialize and review

Keep state outside Git in a private directory:

```sh
install -d -m 700 "$HOME/.local/state/opentofu/dion"
umask 077
tofu init -backend-config="path=$HOME/.local/state/opentofu/dion/terraform.tfstate"
tofu fmt -check
tofu validate
tofu plan
```

Use the same absolute backend path from every checkout. Keep the state and its
backup secure and backed up outside the laptop. State ties resource addresses
to real VMs; losing it can make OpenTofu try to create duplicates. Local state
is for one operator on this laptop, not concurrent runs from several machines.
Commit `.terraform.lock.hcl` when intentionally updating the provider. Do not
commit `.terraform/`, state, saved plans or credentials. Do not copy this
initialized directory to another machine: initialize a checkout against the
correct state instead.

With an empty state, this configuration plans all three VMs. Do not apply that
plan to an existing deployment: initialize against the existing state instead.
Review the full plan before running:

```sh
tofu apply
```

`apply` shows another plan and asks for confirmation. It creates and starts the
VMs; an empty disk falls through to the attached Talos ISO. It does not install
Talos. Agent IP discovery is disabled so provisioning can finish before Talos
has been configured; find addresses in the consoles or OpenWrt leases.

## Install Talos manually

The existing `local:iso/metal-amd64.iso` must be the Talos v1.14.4 Image Factory
ISO with `siderolabs/qemu-guest-agent`, schematic
`ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515`.
The configuration attaches that uploaded file; it does not download or verify it.
Use the matching installer image in Talos configuration.

Reserve each MAC's address in OpenWrt before generating cluster configuration.
DHCP must be enabled on `services`, with UDP 67 allowed to the router. Set the
Talos hostnames explicitly to match the VM names; Proxmox names do not set guest
hostnames. Install to `/dev/sda` after confirming the disks. Apply the control
plane and worker configurations to their respective nodes, bootstrap only the
control plane once, and keep its default `NoSchedule` taint.

Keep Talos configuration and secrets outside Git. A rebuilt cluster is separate
from the old one; decide whether to reuse its secrets before generating configs.
After installation, disk boot takes priority over the ISO. To detach the ISO,
change `cdrom.file_id` to `"none"` in `main.tf` and review another plan rather
than changing it only in the Proxmox UI.

## NixOS oren VM

`oren.tf` manages oren, the NixOS VM that runs agents and T3 Code. It boots
from `scsi0` with an empty CD-ROM.

| Proxmox name | ID | vCPU | RAM | System disk | MAC |
| --- | --- | --- | --- | --- | --- |
| oren-nixos | 111 | 8 | 16 GiB | 256 GiB | 02:00:00:04:01:14 |

The NIC is VirtIO on `vmbr0`, VLAN 4, with the Proxmox firewall enabled. The
guest sets `192.168.4.101/24` on `ens18` statically, with gateway and DNS
`192.168.4.1`; keep `.101` out of dynamic allocation. Clients reach it on TCP 22
and 3773. The Proxmox name is `oren-nixos`; the guest hostname is `oren`.

Dotfiles owns the guest: its system configuration, its Forgejo and GitHub
credentials and its rebuilds. Keep oren out of `inventory.yml` and the
Ansible playbooks.

To reinstall from scratch:

1. Upload the NixOS 26.05 minimal x86_64 ISO to dion's `local` storage as
   `nixos-minimal-26.05-x86_64-linux.iso`. Check its source and checksum.
   Temporarily set `oren.tf`'s `cdrom.file_id` to
   `"local:iso/nixos-minimal-26.05-x86_64-linux.iso"`, review a plan that
   changes only that, and apply it. OpenTofu does not download or verify the
   ISO.
2. Boot the ISO from the Proxmox console. OVMF, q35, an EFI variables disk
   without pre-enrolled keys, host CPU, VirtIO SCSI and `scsi0` match the guest
   configuration. The installer uses DHCP.
3. Follow the dotfiles oren installation instructions, using
   `nixosConfigurations.oren` from the root-owned clone at `/srv/dotfiles`.
   Verify UEFI and `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0`
   before running disko, which erases that disk.
4. Set `cdrom.file_id` back to `"none"`, review a plan and apply.
5. Verify the QEMU guest agent, root SSH from the laptops, the `agent`
   session (`machinectl shell agent@`), rootless Docker and T3 pairing on
   TCP 3773.

## Later changes

Edit the relevant `.tf` file, then run `tofu plan` before `tofu apply`. Configuration changes
can stop or restart VMs; automatic update reboots are disabled, so changes that
require taking a VM offline may fail until you arrange a maintenance window.
Disk growth is supported; shrinking is not a safe rollback.

`prevent_destroy` blocks planned deletion or replacement while the resource
block remains. Removing the whole resource block also removes that guard.
It does not protect against deletion in Proxmox. Do not run `tofu destroy` or
remove the guard as routine maintenance.

## References

- [Proxmox VM resource v0.120.0](https://github.com/bpg/terraform-provider-proxmox/blob/v0.120.0/docs/resources/virtual_environment_vm.md)
- [Talos v1.14 on Proxmox](https://docs.siderolabs.com/talos/v1.14/platform-specific-installations/virtualized-platforms/proxmox)
- [OpenTofu local state](https://opentofu.org/docs/language/settings/backends/local/)
