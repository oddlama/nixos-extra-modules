{
  inputs,
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
in
{
  options.globals = {
    optModules = mkOption {
      type = types.listOf types.deferredModule;
      default = [ ];
      description = ''
        Modules defining global options.
        These should not include any config only option declaration.
        Will be included in the exported nixos Modules from this flake to be included
        into the host evaluation.
      '';
    };
    defModules = mkOption {
      type = types.listOf types.deferredModule;
      default = [ ];
      description = ''
        Modules configuring global options.
        These should not include any option declaration use {option}`optModules` for that.
        Will not included in the exported nixos Modules.
      '';
    };
    attrkeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        The toplevel attrNames for your globals.
        Make sure the keys of this attrset are trivially evaluatable to avoid infinite recursion,
        therefore we inherit relevant attributes from the config.
      '';
    };
  };
  config.flake = flakeSubmod: {
    globals =
      let
        globalsSystem = lib.evalModules {
          prefix = [ "globals" ];
          specialArgs = {
            inherit (inputs.self.pkgs.x86_64-linux) lib;
            inherit inputs;
            inherit (flakeSubmod.config) nodes;
          };
          modules =
            config.globals.optModules
            ++ config.globals.defModules
            ++ [
              ../modules/globals.nix
              (
                { lib, ... }:
                {
                  globals = lib.mkMerge (
                    lib.concatLists (
                      lib.flip lib.mapAttrsToList flakeSubmod.config.nodes (
                        name: cfg:
                        builtins.addErrorContext "while aggregating globals from nixosConfigurations.${name} into flake-level globals:" cfg.config._globalsDefs
                      )
                    )
                  );
                }
              )
            ];
        };
      in
      lib.genAttrs config.globals.attrkeys (x: globalsSystem.config.globals.${x});
  };
}
