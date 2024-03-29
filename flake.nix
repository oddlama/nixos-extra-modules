{
  description = "Extra modules that nobody needs.";

  inputs = {
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    lib-net = {
      url = "https://gist.github.com/duairc/5c9bb3c922e5d501a1edb9e7b3b845ba/archive/3885f7cd9ed0a746a9d675da6f265d41e9fd6704.tar.gz";
      flake = false;
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    devshell,
    pre-commit-hooks,
    ...
  } @ inputs:
    {
      nixosModules.nixos-extra-modules = import ./modules;
      nixosModules.default = self.nixosModules.nixos-extra-modules;
      homeManagerModules.nixos-extra-modules = import ./hm-modules;
      homeManagerModules.default = self.homeManagerModules.nixos-extra-modules;
      overlays.nixos-extra-modules = import ./lib inputs;
      overlays.default = self.overlays.nixos-extra-modules;
    }
    // flake-utils.lib.eachDefaultSystem (system: rec {
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          devshell.overlays.default
        ];
      };

      # `nix flake check`
      checks.pre-commit-hooks = pre-commit-hooks.lib.${system}.run {
        src = nixpkgs.lib.cleanSource ./.;
        hooks = {
          alejandra.enable = true;
          deadnix.enable = true;
          statix.enable = true;
        };
      };

      # `nix fmt`
      formatter = pkgs.alejandra;

      # `nix develop`
      devShells.default = pkgs.devshell.mkShell {
        name = "nixos-extra-modules";
        commands = with pkgs; [
          {
            package = alejandra;
            help = "Format nix code";
          }
          {
            package = statix;
            help = "Lint nix code";
          }
          {
            package = deadnix;
            help = "Find unused expressions in nix code";
          }
        ];

        devshell.startup.pre-commit.text = self.checks.${system}.pre-commit-hooks.shellHook;
      };
    });
}
