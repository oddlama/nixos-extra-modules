{
  description = "Extra modules that nobody needs.";

  inputs = {
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts.url = "github:hercules-ci/flake-parts";

    lib-net = {
      url = "https://gist.github.com/duairc/5c9bb3c922e5d501a1edb9e7b3b845ba/archive/3885f7cd9ed0a746a9d675da6f265d41e9fd6704.tar.gz";
      flake = false;
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, ... }@inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.devshell.flakeModule
        inputs.pre-commit-hooks.flakeModule
      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      flake.modules = {
        nixos = {
          nixos-extra-modules = import ./modules;
          default = self.modules.nixos.nixos-extra-modules;
        };
        home-manager = {
          nixos-extra-modules = import ./hm-modules;
          default = self.modules.home-manager.nixos-extra-modules;
        };
      };
      flake.overlays = {
        nixos-extra-modules = import ./overlay.nix inputs;
        default = self.overlays.nixos-extra-modules;
      };

      perSystem =
        {
          pkgs,
          system,
          config,
          ...
        }:
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [
              self.overlays.default
            ];
          };
          # `nix flake check`
          pre-commit.settings.hooks = {
            nixfmt-rfc-style.enable = true;
            deadnix.enable = true;
            statix.enable = true;
          };
          formatter = pkgs.nixfmt-rfc-style;
          devshells.default = {
            commands = with pkgs; [
              {
                package = statix;
                help = "Lint nix code";
              }
              {
                package = deadnix;
                help = "Find unused expressions in nix code";
              }
            ];
            devshell.startup.pre-commit.text = config.pre-commit.installationScript;
          };
        };
    };
}
