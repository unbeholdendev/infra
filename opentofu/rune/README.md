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

Before the first apply, confirm VM ID 110 is free on rune, and upload the NixOS
26.05 minimal ISO to `local` as `nixos-minimal-26.05-x86_64-linux.iso`. The
first plan should show one addition. `apply` creates the VM and boots the ISO.
After NixOS is installed, set `cdrom.file_id` to `"none"` and apply again.
