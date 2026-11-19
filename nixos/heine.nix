{ pkgs, ... }:

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
        labels = [ "docker:docker://catthehacker/ubuntu:act-latest" ];
      };
      build = {
        enable = true;
        name = "heine-build";
        url = "https://git.home.unbeholden.dev";
        tokenFile = "/etc/forgejo-runner/token";
        labels = [ "docker-build:docker://catthehacker/ubuntu:act-latest" ];
        settings.container.docker_host = "automount";
      };
    };
  };

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" ];
    openFirewall = true;
    firewallFilter = "-p tcp -s 192.168.4.133 --dport 9100";
  };

  networking = {
    hostName = "heine";
    useDHCP = false;
    interfaces.ens18.ipv4.addresses = [{ address = "192.168.4.16"; prefixLength = 24; }];
    defaultGateway = "192.168.4.1";
    nameservers = [ "192.168.4.1" ];
  };

  system.stateVersion = "26.05";
}
