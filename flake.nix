{
  inputs = {
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  description = "Extra modules that nobody needs.";
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    devshell,
    pre-commit-hooks,
    ...
  }:
    {
      nixosModules.extra-modules = import ./modules;
      nixosModules.default = self.nixosModules.extra-modules;
      homeManagerModules.extra-modules = import ./hm-modules;
      homeManagerModules.default = self.homeManagerModules.extra-modules;
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

      # `nix develop`
      devShells.default = pkgs.devshell.mkShell {
        name = "extra-modules";
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
