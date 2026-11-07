{ config, lib, modulesPath, pkgs, ... }:

let
  keyDir = ../keys/admin;
in
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  nix-bitcoin = {
    generateSecrets = true;
    configVersion = "0.1.4";
    secrets = {
      fulcrum-ssl-key.user = "fulcrum";
      fulcrum-ssl-cert.user = "fulcrum";
    };
  };

  services.bitcoind = {
    enable = true;
    dataDir = "/data/bitcoind";
  };

  services.lnd = {
    enable = true;
    dataDir = "/data/lnd";
    rpcAddress = "0.0.0.0";
    certificate.extraIPs = [ "192.168.4.11" ];
  };

  services.fulcrum = {
    enable = true;
    dataDir = "/data/fulcrum";
    extraConfig = ''
      ssl = 0.0.0.0:50002
      cert = ${config.nix-bitcoin.secretsDir}/fulcrum-ssl-cert
      key = ${config.nix-bitcoin.secretsDir}/fulcrum-ssl-key
    '';
  };

  # bitcoinix creates a new wallet when none exists; this node only runs the migrated one.
  systemd.services.lnd.unitConfig.ConditionPathExists = "/data/lnd/chain/bitcoin/mainnet/wallet.db";

  fileSystems."/mnt/lnd-backup" = {
    device = "192.168.5.2:/mnt/storage/lnd-backups";
    fsType = "nfs";
    options = [ "nfsvers=4.2" "noauto" "x-systemd.automount" "x-systemd.idle-timeout=600" ];
  };

  systemd.paths.lnd-channel-backup = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathChanged = "/data/lnd/chain/bitcoin/mainnet/channel.backup";
  };

  systemd.timers.lnd-channel-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnCalendar = "hourly";
    };
  };

  systemd.services.lnd-channel-backup = {
    unitConfig.RequiresMountsFor = "/mnt/lnd-backup";
    serviceConfig.Type = "oneshot";
    path = [ pkgs.diffutils ];
    script = ''
      cmp -s /data/lnd/chain/bitcoin/mainnet/channel.backup /mnt/lnd-backup/channel.backup && exit 0
      install -m 600 /data/lnd/chain/bitcoin/mainnet/channel.backup /mnt/lnd-backup/channel.backup.tmp
      mv /mnt/lnd-backup/channel.backup.tmp /mnt/lnd-backup/channel.backup
    '';
  };

  fileSystems."/data" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1";
    fsType = "ext4";
  };

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

  networking = {
    hostName = "goddard";
    useDHCP = false;
    interfaces.ens18.ipv4.addresses = [{ address = "192.168.4.11"; prefixLength = 24; }];
    defaultGateway = "192.168.4.1";
    nameservers = [ "192.168.4.1" ];
    nftables.enable = true;
    firewall.extraInputRules = ''
      ip saddr { 192.168.4.12, 192.168.1.0/24, 100.64.0.3 } tcp dport 10009 accept
      ip saddr { 192.168.4.12, 192.168.1.0/24, 100.64.0.5 } tcp dport 50002 accept
    '';
  };

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

  system.stateVersion = "26.05";
}
