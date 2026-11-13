resource "proxmox_virtual_environment_vm" "oren" {
  node_name           = "dion"
  vm_id               = 111
  name                = "oren-nixos"
  bios                = "ovmf"
  machine             = "q35"
  scsi_hardware       = "virtio-scsi-pci"
  boot_order          = ["scsi0", "ide2"]
  on_boot             = true
  started             = true
  reboot_after_update = false

  cpu {
    cores = 8
    type  = "host"
  }

  memory {
    dedicated = 16384
    floating  = 16384
  }

  agent {
    enabled = true

    wait_for_ip {
      disabled = true
    }
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    file_format  = "raw"
    size         = 256
    cache        = "none"
    discard      = "on"
    ssd          = true
  }

  cdrom {
    file_id   = "none"
    interface = "ide2"
  }

  network_device {
    bridge      = "vmbr0"
    vlan_id     = 4
    model       = "virtio"
    firewall    = true
    mac_address = "02:00:00:04:01:14"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    prevent_destroy = true
  }
}
