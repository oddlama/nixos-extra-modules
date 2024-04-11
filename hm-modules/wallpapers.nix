{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.xsession.wallpapers;
in {
  options.xsession.wallpapers = {
    enable = lib.mkEnableOption "automatically refreshing randomly selected wallpapers";
    script = let
      exe =
        pkgs.writeShellScript "set-wallpaper"
        ''
             ${pkgs.feh}/bin/feh --no-fehbg --bg-fill --randomize \
          $( ${pkgs.findutils}/bin/find ${config.home.homeDirectory}/${cfg.folder} \( -iname "*.png" -or -iname "*.jpg" \) )
        '';
    in
      lib.mkOption {
        description = "The script which will be called to set new wallpapers";
        default = exe;
        type = lib.types.package;
      };
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
  config = lib.mkIf cfg.enable {
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
              cfg.script;
          };
          Install.WantedBy = ["graphical-session.target"];
        };
      };
    };
    home.persistence."/state".directories = [cfg.folder];
  };
}
