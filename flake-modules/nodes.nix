{
  inputs,
  self,
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  topConfig = config;
in
{
  options.node = {
    path = mkOption {
      type = types.path;
      description = "The path containing your host definitions";
    };
    nixpkgs = mkOption {
      type = types.path;
      default = inputs.nixpkgs;
      description = "The path to your nixpkgs.";
    };
  };
  config.flake =
    {
      config,
      lib,
      ...
    }:
    let
      inherit (lib)
        concatMapAttrs
        filterAttrs
        flip
        genAttrs
        mapAttrs'
        nameValuePair
        ;

      # Creates a new nixosSystem with the correct specialArgs, pkgs and name definition
      mkHost =
        { minimal }:
        name:
        let
          pkgs = config.pkgs.x86_64-linux;
        in
        (import "${topConfig.node.nixpkgs}/nixos/lib/eval-config.nix") {
          system = null;
          specialArgs = {
            # Use the correct instance lib that has our overlays
            inherit (pkgs) lib;
            inherit (config) nodes globals;
            inherit minimal;
            extraModules = [
              ../modules
            ] ++ topConfig.globals.optModules;
            inputs = inputs // {
              inherit (topConfig.node) nixpkgs;
            };
          };
          modules = [
            (
              { config, ... }:
              {
                node.name = name;
                node.secretsDir = topConfig.node.path + "/${name}/secrets";
                nixpkgs.pkgs = self.pkgs.${config.nixpkgs.hostPlatform.system};
              }
            )
            (topConfig.node.path + "/${name}")
            ../modules
          ] ++ topConfig.globals.optModules;
        };

      # Load the list of hosts that this flake defines, which
      # associates the minimum amount of metadata that is necessary
      # to instanciate hosts correctly.
      hosts = builtins.attrNames (
        filterAttrs (_: type: type == "directory") (builtins.readDir topConfig.node.path)
      );
    in
    # Process each nixosHosts declaration and generatea nixosSystem definitions
    {
      nixosConfigurations = genAttrs hosts (mkHost {
        minimal = false;
      });
      minimalConfigurations = genAttrs hosts (mkHost {
        minimal = true;
      });

      # True NixOS nodes can define additional guest nodes that are built
      # together with it. We collect all defined guests from each node here
      # to allow accessing any node via the unified attribute `nodes`.
      guestConfigurations = flip concatMapAttrs config.nixosConfigurations (
        _: node:
        flip mapAttrs' (node.config.guests or { }) (
          guestName: guestDef:
          nameValuePair guestDef.nodeName (
            if guestDef.backend == "microvm" then
              node.config.microvm.vms.${guestName}.config
            else
              node.config.containers.${guestName}.nixosConfiguration
          )
        )
      );
      # All nixosSystem instanciations are collected here, so that we can refer
      # to any system via nodes.<name>
      nodes = config.nixosConfigurations // config.guestConfigurations;
    };
}
