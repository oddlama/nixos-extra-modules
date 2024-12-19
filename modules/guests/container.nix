guestName: guestCfg: {
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    flip
    mapAttrs'
    nameValuePair
    ;
in {
  inherit (guestCfg.container) macvlans;
  ephemeral = true;
  privateNetwork = true;
  autoStart = guestCfg.autostart;
  extraFlags = [
    "--uuid=${builtins.substring 0 32 (builtins.hashString "sha256" guestName)}"
  ];
  bindMounts = flip mapAttrs' guestCfg.zfs (
    _: zfsCfg:
      nameValuePair zfsCfg.guestMountpoint {
        hostPath = zfsCfg.hostMountpoint;
        isReadOnly = false;
      }
  );
  nixosConfiguration = (import "${inputs.nixpkgs}/nixos/lib/eval-config.nix") {
    specialArgs = guestCfg.extraSpecialArgs;
    prefix = [
      "nodes"
      "${config.node.name}-${guestName}"
      "config"
    ];
    system = null;
    modules =
      [
        {
          boot.isContainer = true;
          networking.useHostResolvConf = false;

          # We cannot force the package set via nixpkgs.pkgs and
          # inputs.nixpkgs.nixosModules.readOnlyPkgs, since some nixosModules
          # like nixseparatedebuginfod depend on adding packages via nixpkgs.overlays.
          # So we just mimic the options and overlays defined by the passed pkgs set.
          nixpkgs.hostPlatform = config.nixpkgs.hostPlatform.system;
          nixpkgs.overlays = pkgs.overlays;
          nixpkgs.config = pkgs.config;

          # Bind the /guest/* paths from above so impermancence doesn't complain.
          # We bind-mount stuff from the host to itself, which is perfectly defined
          # and not recursive. This allows us to have a fileSystems entry for each
          # bindMount which other stuff can depend upon (impermanence adds dependencies
          # to the state fs).
          fileSystems = flip mapAttrs' guestCfg.zfs (
            _: zfsCfg:
              nameValuePair zfsCfg.guestMountpoint {
                neededForBoot = true;
                fsType = "none";
                device = zfsCfg.guestMountpoint;
                options = ["bind"];
              }
          );
        }
        (import ./common-guest-config.nix guestName guestCfg)
      ]
      ++ guestCfg.modules;
  };
}
