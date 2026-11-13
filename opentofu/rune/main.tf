terraform {
  required_version = ">= 1.13.0, < 2.0.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.120.0"
    }
  }

  backend "local" {}
}

provider "proxmox" {
  endpoint = "https://192.168.6.2:8006/"
}

resource "proxmox_virtual_environment_vm" "goddard" {
  node_name           = "rune"
  vm_id               = 110
  name                = "goddard"
  bios                = "ovmf"
  machine             = "q35"
  scsi_hardware       = "virtio-scsi-pci"
  boot_order          = ["scsi0", "ide2"]
  on_boot             = true
  started             = true
  reboot_after_update = false

  # The data disk on scsi1 is attached by hand and must survive a destroy.
  delete_unreferenced_disks_on_destroy = false

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 8192
    floating  = 8192
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
    size         = 32
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
    mac_address = "02:00:00:04:01:11"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    prevent_destroy = true
  }
}
