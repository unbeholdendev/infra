{
  inputs = {
    bitcoinix.url = "github:bitcoinix/bitcoinix/v0.1.5";
    nixpkgs.follows = "bitcoinix/nixpkgs";
    nixpkgs-unstable.follows = "bitcoinix/nixpkgs-unstable";
    disko = {
      url = "github:nix-community/disko/v1.13.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, bitcoinix, disko, ... }: {
    nixosConfigurations.goddard = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        bitcoinix.nixosModules.default
        disko.nixosModules.disko
        ./nixos/goddard.nix
      ];
    };
  };
}
