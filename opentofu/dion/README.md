# Dion VMs

OpenTofu runs on the NixOS laptop and manages only the Proxmox VMs. Talos
configuration, Kubernetes bootstrap, DHCP reservations and application deployment
remain manual. No Talos credentials belong in this directory.

| VM | ID | vCPU | RAM | Disk | MAC |
| --- | --- | --- | --- | --- | --- |
| talos-cp-01 | 100 | 2 | 4 GiB | 20 GiB | 02:00:00:04:01:01 |
| talos-worker-01 | 101 | 4 | 8 GiB | 32 GiB | 02:00:00:04:01:02 |

For the original Talos setup only, the VMs use Dion's `local-lvm`, `vmbr0`
and VLAN 4. For the oren addition, skip the original setup and use
[the oren steps below](#nixos-oren-vm); do not
remove any existing VM. Remove the pre-Talos VM 100
manually before applying: OpenTofu neither imports nor deletes it. Confirm IDs
100 and 101 are free across the Proxmox cluster, check actual storage capacity,
and review these starting sizes before applying. Thin provisioning does not
remove the need to monitor pool usage.

## Access

After merging the dotfiles change, run `dots` on the laptop to install `tofu`.
Run the commands below from this directory.

Use a dedicated Proxmox API token, not root's password. Set
`PROXMOX_VE_API_TOKEN` in the environment to `user@realm!tokenid=secret`, without
putting the value in shell history or this repository. Keep the token in a
private file or password manager. A privilege-separated token needs permissions
on both the user and token.

Scope VM permissions to `/vms/100` and `/vms/101`. Add `/vms/111` once the
proposed oren ID is confirmed. Scope storage permissions to
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

With an empty state, this configuration now plans all three VMs. Do not apply
that plan to an existing deployment. The oren addition has its own plan
expectations below.
This original setup assumed the pre-Talos VM 100 was untracked and already
removed. It does not apply to adding oren to the managed Talos setup. Review
the full plan before running:

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

`oren.tf` manages the new VM on dion alongside old oren. The installed VM
boots from `scsi0`; its CD-ROM is empty. A full plan should show only ISO
detachment if it is still attached, or no changes if it was detached in the UI.
Stop if the plan replaces a VM or changes another resource.

| Proxmox name | ID | vCPU | RAM | System disk | MAC |
| --- | --- | --- | --- | --- | --- |
| oren-nixos | 111 | 8 | 16 GiB | 256 GiB | 02:00:00:04:01:14 |

These are proposed allocations, not verified live reservations. Before applying,
the owner must confirm ID 111 is free across the cluster, the name and MAC are
unused, and dion has CPU, RAM and `local-lvm` capacity alongside its current
workloads. The existing Talos definitions allocate 6 vCPU, 12 GiB RAM and 52 GiB
of disk in total. They do not describe dion's total capacity or all live guests.
The proposed 256 GiB disk leaves more room for Nix store paths, builds, project
checkouts and rootless Docker images than goddard's 32 GiB system disk, whose
data lives on a separate disk. It is a starting size, not measured demand.

The NIC follows the existing VMs: VirtIO on `vmbr0`, VLAN 4, with the Proxmox
firewall enabled. Old oren remains at `192.168.4.13` in `inventory.yml` and in
its Ansible groups. Keep the NixOS guest out of the old Debian Ansible groups;
dotfiles manages its system configuration. Its static IPv4 configuration uses
`192.168.4.101/24` on `ens18`, with gateway and DNS `192.168.4.1`, matching
goddard's guest-side configuration pattern. DHCP is disabled in the installed
guest. Before switching, verify `ens18` is the VM's VirtIO NIC and exclude
`.101` from dynamic allocation or reserve it for MAC `02:00:00:04:01:14`.
The live installer can still use DHCP before the guest configuration is applied.
Do not reuse old oren's address or DNS entry during installation. The Proxmox
name is `oren-nixos`; the dotfiles guest hostname remains `oren`. Set any new
DNS record explicitly without replacing old oren's record during migration.
Router, DNS, DHCP and firewall policy changes are separate work. Verify the
intended client can reach TCP 22 and 3773 through network and Proxmox rules;
the guest opening those ports alone does not establish network access.

For a fresh installation, follow these steps. Do not repeat disko on the
installed VM.

1. Upload the NixOS 26.05 minimal x86_64 ISO to dion's `local` storage as
   `nixos-minimal-26.05-x86_64-linux.iso`. Check its source and checksum.
   Temporarily set `oren.tf`'s `cdrom.file_id` to
   `"local:iso/nixos-minimal-26.05-x86_64-linux.iso"`. OpenTofu does not
   download or verify the ISO.
2. Use the existing dion backend path above, including its current Talos state.
   Extend the API token scope only to the confirmed new VM ID. Review a full
   `tofu plan`. With the Talos VMs already managed, expect exactly one addition,
   `proxmox_virtual_environment_vm.oren`, and no changes, replacements or
   deletions. Stop if either Talos VM appears as an addition or change, or if
   old oren appears anywhere in the plan. Do not use an empty backend or a
   targeted apply to bypass an unexpected plan.
3. After the allocation and capacity checks, apply the
   reviewed configuration. This creates and starts an empty VM; it does not
   install NixOS. Use the Proxmox console to boot the ISO. OVMF, q35, an EFI
   variables disk without pre-enrolled keys, host CPU, VirtIO SCSI and `scsi0`
   match the guest configuration. Agent IP waiting stays disabled during
   installation; find the new address in the console or router leases.
4. Follow the dotfiles oren installation instructions. The base ISO runs the
   installer; `nixos-install` downloads and builds the guest configuration
   inside the VM. Use `nixosConfigurations.oren` from the root-owned dotfiles
   clone, not this repository's `nixos/` configuration. Use this VM's proposed
   8 vCPU, 16 GiB RAM and 256 GiB disk.
   Verify UEFI and
   `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0` in the console before
   running disko, which erases that disk. Install only on the new VM's disk.
5. After installation, set only `oren.tf`'s `cdrom.file_id` to `"none"` and
   review another plan before applying. Boot from `scsi0` and verify the QEMU
   guest agent, root console login, the unprivileged `agent` session, rootless
   Docker and Compose, and T3 pairing on TCP 3773.
6. Apply dotfiles' key-only SSH configuration from the VM's root console:

   ```sh
   cd /srv/dotfiles
   git pull --ff-only
   nixos-rebuild switch --flake /srv/dotfiles#oren
   ```

   Connect from the T14 or T460s with `ssh root@<VM-IP>`. Password SSH login
   is disabled. Use `machinectl shell agent@` for the agent session. Do not
   use the old Ansible playbooks to install Docker or root's Forgejo token.

The guest configuration belongs to dotfiles. Moving T3 state and credentials,
cutting over addresses or DNS, and retiring the old host and its inventory or
playbooks are separate work. Keep the old host running until those steps are
agreed and checked. Review a live plan before applying this cleanup.

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
