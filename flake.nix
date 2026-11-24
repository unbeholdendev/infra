{
  inputs = {
    bitcoinix.url = "github:bitcoinix/bitcoinix/v0.2.0";
    nixpkgs.follows = "bitcoinix/nixpkgs";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko = {
      url = "github:nix-community/disko/v1.13.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixpkgs-stable, bitcoinix, disko, ... }: {
    nixosConfigurations.goddard = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        bitcoinix.nixosModules.default
        disko.nixosModules.disko
        ./nixos/goddard.nix
      ];
    };

    nixosConfigurations.heine = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        ./nixos/heine.nix
      ];
    };

    packages.x86_64-linux.mcp-grafana =
      nixpkgs.legacyPackages.x86_64-linux.mcp-grafana;

    devShells.x86_64-linux.default =
      let pkgs = nixpkgs.legacyPackages.x86_64-linux;
      in pkgs.mkShell {
        packages = with pkgs; [
          ansible
          fluxcd
          kubectl
          kubernetes-helm
          opentofu
          sops
          talosctl
        ];
      };
  };
}
