{
  lib,
  config,
  pkgs,
  ...
}: {
  options.xsession.windowManager.i3.enableSystemdTarget = lib.mkEnableOption "i3 autostarting the systemd graphical user targets";
  config = let
    cfg = config.xsession.windowManager.i3.enableSystemdTarget;
  in
    lib.mkIf cfg {
      systemd.user = {
        targets.i3-session = {
          Unit = {
            Description = "i3 session";
            Documentation = ["man:systemd.special(7)"];
            BindsTo = ["graphical-session.target"];
            Wants = ["graphical-session-pre.target"];
            After = ["graphical-session-pre.target"];
          };
        };
      };
      xsession.windowManager.i3.config.startup = lib.mkAfter [
        {
          command = "${pkgs.systemd}/bin/systemctl --user start i3-session.target";
          always = false;
          notification = false;
        }
      ];
    };
}
