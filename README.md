[Installation](#installation)

# 🍵 nixos-extra-modules

This repository contains extra modules for nixos that are very opinionated and mainly
useful to me and my colleagues.

## Installation

To use the extra modules, you will have to add this project to your `flake.nix`,
and import the provided main NixOS module in your hosts. Afterwards the new options
will be available.

```nix
{
  inputs.extra-modules.url = "github:oddlama/extra-modules";

  outputs = { self, nixpkgs, agenix, agenix-rekey }: {
    # Example system configuration
    nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        agenix.nixosModules.default
        extra-modules.nixosModules.default
      ];
    };
  }
}
