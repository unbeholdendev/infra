{ lib, modulesPath, ... }:

let
  keyDir = ../keys/admin;
in
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  disko.devices.disk.boot = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  services.qemuGuest.enable = true;
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  users.users.root.openssh.authorizedKeys.keys =
    map (f: builtins.readFile (keyDir + "/${f}"))
      (builtins.attrNames (lib.filterAttrs (n: _: lib.hasSuffix ".pub" n) (builtins.readDir keyDir)));
}
