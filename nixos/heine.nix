{ pkgs, ... }:

let
  image = "docker://catthehacker/ubuntu:act-latest@sha256:a17ca1ab0676e450e5383024da90a53521edbbcf1e85b13a4d4a20bd5663eaa9";
in
{
  imports = [ ./vm.nix ];

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances = {
      heine = {
        enable = true;
        name = "heine";
        url = "https://git.home.unbeholden.dev";
        tokenFile = "/etc/forgejo-runner/token";
        labels = [ "docker:${image}" ];
      };
      build = {
        enable = true;
        name = "heine-build";
        url = "https://git.home.unbeholden.dev";
        tokenFile = "/etc/forgejo-runner/token";
        labels = [ "docker-build:${image}" ];
        settings.container.docker_host = "automount";
      };
    };
  };

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" ];
  };

  networking = {
    hostName = "heine";
    useDHCP = false;
    interfaces.ens18.ipv4.addresses = [{ address = "192.168.4.16"; prefixLength = 24; }];
    defaultGateway = "192.168.4.1";
    nameservers = [ "192.168.4.1" ];
    firewall.extraCommands = ''
      iptables -A nixos-fw -p tcp -s 192.168.4.133 --dport 9100 -j nixos-fw-accept
    '';
  };

  system.stateVersion = "26.05";
}
