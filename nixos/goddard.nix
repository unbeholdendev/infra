{ config, lib, pkgs, ... }:

{
  imports = [ ./vm.nix ];

  nix-bitcoin = {
    generateSecrets = true;
    configVersion = "0.2.0";
    secrets = {
      fulcrum-ssl-key.user = "fulcrum";
      fulcrum-ssl-cert.user = "fulcrum";
      unbeholden-lnurl-ntfy-token.user = "unbeholden-lnurl";
      unbeholden-lnurl-webhook-stackorange.user = "unbeholden-lnurl";
      unbeholden-lnurl-payments-stackorange.user = "unbeholden-lnurl";
    };
  };

  services.bitcoind = {
    enable = true;
    dataDir = "/data/bitcoind";
  };

  services.lnd = {
    enable = true;
    dataDir = "/data/lnd";
    rpcAddress = "192.168.4.11";
    # bitcoinix grants payment RPCs only for withdraw vouchers and lacks TrackPaymentV2.
    macaroons.unbeholden-lnurl.permissions = lib.mkForce (lib.concatMapStringsSep ","
      (method: builtins.toJSON { entity = "uri"; action = method; }) [
        "/lnrpc.Lightning/AddInvoice"
        "/lnrpc.Lightning/LookupInvoice"
        "/lnrpc.Lightning/ListInvoices"
        "/lnrpc.Lightning/SubscribeInvoices"
        "/lnrpc.Lightning/GetInfo"
        "/routerrpc.Router/SendPaymentV2"
        "/routerrpc.Router/TrackPaymentV2"
      ]);
  };

  services.fulcrum = {
    enable = true;
    dataDir = "/data/fulcrum";
    extraConfig = ''
      ssl = 192.168.4.11:50002
      cert = ${config.nix-bitcoin.secretsDir}/fulcrum-ssl-cert
      key = ${config.nix-bitcoin.secretsDir}/fulcrum-ssl-key
    '';
  };

  services.unbeholden-wallet = {
    enable = true;
    address = "0.0.0.0";
    allowedClients = [ "192.168.4.133" ];
    allowedHosts = [ "wallet.home.unbeholden.dev" ];
    electrumServer = "fulcrum";
  };

  services.unbeholden-lnurl = {
    enable = true;
    # bitcoinix v0.2.0 packages 0.4.0; drop once it ships 0.6.0 or later.
    package = config.nix-bitcoin.pkgs.unbeholden-lnurl.overrideAttrs (old: rec {
      version = "0.6.0";
      src = old.src.override {
        tag = "v${version}";
        hash = "sha256-/mvPwfj3U/EU0Tuyn4qg5SFaT4ojqGuF315Mv1GvhTo=";
      };
      ldflags = [ "-s" "-w" "-X main.version=v${version}" ];
    });
    address = "192.168.4.11";
    settings = {
      trusted_proxies = [ "192.168.4.133" ];
      addresses."*" = {
        description = "Much appreciated!";
        success_message = "Thank you for your contribution";
        min_sendable = 1000;
        max_sendable = 1000000000;
      };
      notifications.ntfy = {
        url = "https://ntfy.unbeholden.dev";
        topic = "lnd";
        token_file = "${config.nix-bitcoin.secretsDir}/unbeholden-lnurl-ntfy-token";
      };
      notifications.webhooks.stackorange = {
        url = "https://stackorange.unbeholden.dev/api/webhooks/lnurl";
        events = [ "payment.received" "payment.sent" "payment.failed" ];
        secret_file = "${config.nix-bitcoin.secretsDir}/unbeholden-lnurl-webhook-stackorange";
      };
      payments.clients.stackorange.token_file =
        "${config.nix-bitcoin.secretsDir}/unbeholden-lnurl-payments-stackorange";
      nostr = {};
    };
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

  networking = {
    hostName = "goddard";
    useDHCP = false;
    interfaces.ens18.ipv4.addresses = [{ address = "192.168.4.11"; prefixLength = 24; }];
    defaultGateway = "192.168.4.1";
    nameservers = [ "192.168.4.1" ];
    nftables.enable = true;
    firewall.extraInputRules = ''
      ip saddr { 192.168.1.0/24, 100.64.0.3 } tcp dport 10009 accept
      ip saddr { 192.168.1.0/24, 100.64.0.5 } tcp dport 50002 accept
      ip saddr 192.168.4.133 tcp dport { 8081, 9100, 60846 } accept
    '';
  };

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" ];
  };

  system.stateVersion = "26.05";
}
