# Rune VMs

OpenTofu manages only the `goddard` VM (ID 110) on rune. Its boot disk comes
from here. Its data disk on `scsi1` is attached by hand (see
[`nixos/README.md`](../../nixos/README.md)) and stays out of the configuration,
so no plan can resize, move or delete it. `delete_unreferenced_disks_on_destroy`
is off, so a destroy also leaves it in place.

Access, the API token, TLS and state work as in
[`opentofu/dion`](../dion/README.md), with rune's endpoint and a token scoped to
`/vms/110`. Keep the state in its own directory:

```sh
install -d -m 700 "$HOME/.local/state/opentofu/rune"
umask 077
tofu init -backend-config="path=$HOME/.local/state/opentofu/rune/terraform.tfstate"
tofu plan
```

The CD-ROM is empty once NixOS is installed. To create the VM from scratch or
reinstall, upload the NixOS 26.05 minimal ISO to `local` as
`nixos-minimal-26.05-x86_64-linux.iso`, set `cdrom.file_id` to
`"local:iso/nixos-minimal-26.05-x86_64-linux.iso"`, and apply. With an empty
boot disk the VM falls through to the CD-ROM. For a new VM, confirm ID 110 is
free on rune first; the plan should show one addition. Set `file_id` back to
`"none"` after the install.
