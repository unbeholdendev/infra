{
  inputs = {
    bitcoinix.url = "github:bitcoinix/bitcoinix/v0.1.6";
    nixpkgs.follows = "bitcoinix/nixpkgs";
    nixpkgs-unstable.follows = "bitcoinix/nixpkgs-unstable";
    disko = {
      url = "github:nix-community/disko/v1.13.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixpkgs-unstable, bitcoinix, disko, ... }: {
    nixosConfigurations.goddard = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        bitcoinix.nixosModules.default
        disko.nixosModules.disko
        ./nixos/goddard.nix
      ];
    };

    nixosConfigurations.heine = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        ./nixos/heine.nix
      ];
    };

    packages.x86_64-linux.mcp-grafana =
      nixpkgs-unstable.legacyPackages.x86_64-linux.mcp-grafana;

    devShells.x86_64-linux.default =
      let pkgs = nixpkgs-unstable.legacyPackages.x86_64-linux;
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
