{
  config,
  lib,
  ...
}: {
  options.boot.mode = lib.mkOption {
    description = "Enable recommended Options for different boot modes";
    type = lib.types.nullOr (lib.types.enum ["bios" "efi" "secureboot"]);
    default = null;
  };
  config.boot.loader = let
    bios-conf = {
      grub = {
        enable = true;
        efiSupport = false;
        configurationLimit = 32;
      };
    };
    efi-conf = {
      # Use the systemd-boot EFI boot loader.
      systemd-boot.enable = true;
      systemd-boot.configurationLimit = 32;
      efi.canTouchEfiVariables = true;
    };
  in
    lib.mkIf (config.boot.mode != null)
    {
      "efi" = efi-conf;
      "bios" = bios-conf;
      "secureboot" = throw "not yet implemented";
    }
    .${config.boot.mode};
}
