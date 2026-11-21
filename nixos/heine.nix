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
        settings = {
          runner.capacity = 3;
          cache.proxy_port = 8088;
        };
      };
      build = {
        enable = true;
        name = "heine-build";
        url = "https://git.home.unbeholden.dev";
        tokenFile = "/etc/forgejo-runner/token";
        labels = [ "docker-build:${image}" ];
        settings = {
          container.docker_host = "automount";
          cache.proxy_port = 8089;
        };
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
    firewall = {
      interfaces."br-+".allowedTCPPorts = [ 8088 8089 ];
      extraCommands = ''
        iptables -A nixos-fw -p tcp -s 192.168.4.133 --dport 9100 -j nixos-fw-accept
      '';
    };
  };

  system.stateVersion = "26.05";
}
