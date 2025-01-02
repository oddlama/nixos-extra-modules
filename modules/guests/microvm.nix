guestName: guestCfg: {
  inputs,
  lib,
  ...
}: let
  inherit
    (lib)
    concatMapAttrs
    flip
    mapAttrs
    mapAttrsToList
    mkDefault
    mkForce
    replaceStrings
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
        (
          {config, ...}: {
            # Set early hostname too, so we can associate those logs to this host and don't get "localhost" entries in loki
            boot.kernelParams = ["systemd.hostname=${config.networking.hostName}"];
          }
        )
      ];

    lib.microvm.interfaces = guestCfg.microvm.interfaces;

    microvm = {
      hypervisor = mkDefault "qemu";

      # Give them some juice by default
      mem = mkDefault (1024 + 2048);
      # This causes QEMU rebuilds which would remove 200MB from the closure but
      # recompiling QEMU every deploy is worse.
      optimize.enable = false;

      # Add a writable store overlay, but since this is always ephemeral
      # disable any store optimization from nix.
      writableStoreOverlay = "/nix/.rw-store";

      # MACVTAP bridge to the host's network
      interfaces = flip mapAttrsToList guestCfg.microvm.interfaces (
        _: {
          mac,
          hostLink,
          ...
        }: {
          type = "macvtap";
          id = "vm-${replaceStrings [":"] [""] mac}";
          inherit mac;
          macvtap = {
            link = hostLink;
            mode = "bridge";
          };
        }
      );

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

    networking.renameInterfacesByMac = flip mapAttrs guestCfg.microvm.interfaces (_: {mac, ...}: mac);
    systemd.network.networks = flip concatMapAttrs guestCfg.microvm.interfaces (
      name: {mac, ...}: {
        "10-${name}".matchConfig = mkForce {
          MACAddress = mac;
        };
      }
    );
  };
}
