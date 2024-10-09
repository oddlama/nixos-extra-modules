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
    mapAttrsToList
    mkDefault
    mkForce
    ;
in {
  specialArgs = guestCfg.extraSpecialArgs;
  pkgs = inputs.self.pkgs.${guestCfg.microvm.system};
  inherit (guestCfg) autostart;
  config = {
    imports =
      guestCfg.modules
      ++ [
        (import ./common-guest-config.nix guestName guestCfg)
        ({config, ...}: {
          # Set early hostname too, so we can associate those logs to this host and don't get "localhost" entries in loki
          boot.kernelParams = ["systemd.hostname=${config.networking.hostName}"];
        })
      ];

    lib.microvm.mac = guestCfg.microvm.mac;

    microvm = {
      hypervisor = mkDefault "qemu";

      # Give them some juice by default
      mem = mkDefault (1024 + 2048);

      # Add a writable store overlay, but since this is always ephemeral
      # disable any store optimization from nix.
      writableStoreOverlay = "/nix/.rw-store";

      # MACVTAP bridge to the host's network
      interfaces = [
        {
          type = "macvtap";
          id = "vm-${guestName}";
          inherit (guestCfg.microvm) mac;
          macvtap = {
            link = guestCfg.microvm.macvtap;
            mode = "bridge";
          };
        }
      ];

      shares =
        [
          # Share the nix-store of the host
          {
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            tag = "ro-store";
            proto = "virtiofs";
          }
        ]
        ++ flip mapAttrsToList guestCfg.zfs (
          _: zfsCfg: {
            source = zfsCfg.hostMountpoint;
            mountPoint = zfsCfg.guestMountpoint;
            tag = builtins.substring 0 16 (builtins.hashString "sha256" zfsCfg.hostMountpoint);
            proto = "virtiofs";
          }
        );
    };

    networking.renameInterfacesByMac.${guestCfg.networking.mainLinkName} = guestCfg.microvm.mac;
    systemd.network.networks."10-${guestCfg.networking.mainLinkName}".matchConfig = mkForce {
      MACAddress = guestCfg.microvm.mac;
    };
  };
}
