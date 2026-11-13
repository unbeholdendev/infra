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
  endpoint = "https://192.168.6.3:8006/"
}

locals {
  nodes = {
    talos-cp-01 = {
      vm_id       = 100
      cores       = 2
      memory      = 4096
      disk_size   = 20
      mac_address = "02:00:00:04:01:01"
    }
    talos-worker-01 = {
      vm_id       = 101
      cores       = 4
      memory      = 8192
      disk_size   = 32
      mac_address = "02:00:00:04:01:02"
    }
  }
}

resource "proxmox_virtual_environment_vm" "talos" {
  for_each = local.nodes

  node_name           = "dion"
  vm_id               = each.value.vm_id
  name                = each.key
  bios                = "ovmf"
  machine             = "q35"
  scsi_hardware       = "virtio-scsi-pci"
  boot_order          = ["scsi0", "ide2"]
  on_boot             = true
  started             = true
  reboot_after_update = false

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
    floating  = each.value.memory
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
    size         = each.value.disk_size
    cache        = "none"
    discard      = "on"
    ssd          = true
  }

  cdrom {
    file_id   = "local:iso/metal-amd64.iso"
    interface = "ide2"
  }

  network_device {
    bridge      = "vmbr0"
    vlan_id     = 4
    model       = "virtio"
    firewall    = true
    mac_address = each.value.mac_address
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    prevent_destroy = true
  }
}
