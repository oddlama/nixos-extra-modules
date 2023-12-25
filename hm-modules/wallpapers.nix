{
  lib,
  config,
  pkgs,
  ...
}: {
  options.xsession.wallpapers = {
    enable = lib.mkEnableOption "automatically refreshing randomly selected wallpapers";
    folder = lib.mkOption {
      description = "The folder from which the wallpapers are selected. Relative to home directory";
      type = lib.types.str;
      default = ".local/share/wallpapers";
    };
    refreshInterval = lib.mkOption {
      description = "How often new wallpapers are drawn. Used as a Systemd timer interval.";
      type = lib.types.str;
      default = "3 min";
    };
  };
  config = let
    cfg = config.xsession.wallpapers;
    exe =
      pkgs.writeShellScript "set-wallpaper"
      ''
           ${pkgs.feh}/bin/feh --no-fehbg --bg-fill --randomize \
        $( ${pkgs.findutils}/bin/find ${config.home.homeDirectory}/${cfg.folder} \( -iname "*.png" -or -iname "*.jpg" \) )
      '';
  in
    lib.mkIf cfg.enable {
      systemd.user = {
        timers = {
          set-wallpaper = {
            Unit = {
              Description = "Set a random wallpaper every 3 minutes";
            };
            Timer = {
              OnUnitActiveSec = cfg.refreshInterval;
            };
            Install.WantedBy = [
              "timers.target"
            ];
          };
        };
        services = {
          set-wallpaper = {
            Unit = {
              Description = "Set a random wallpaper on all X displays";
            };
            Service = {
              Type = "oneshot";
              ExecStart =
                exe;
            };
            Install.WantedBy = ["graphical-session.target"];
          };
        };
      };
      home.persistence."/state".directories = [cfg.folder];
    };
}
