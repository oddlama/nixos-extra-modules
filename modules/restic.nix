{
  lib,
  config,
  ...
}: let
  inherit
    (lib)
    flatten
    flip
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    optional
    types
    unique
    ;
in {
  options.services.restic.backups = mkOption {
    type = types.attrsOf (types.submodule (submod: {
      options.hetznerStorageBox = {
        enable = mkEnableOption "Automatically configure this backup to use the given hetzner storage box. Will use SFTP via SSH.";

        mainUser = mkOption {
          type = types.str;
          description = ''
            The main user. While not technically required for restic, we still use it to
            derive the subuser name and it is required for the automatic setup script
            that creates the users.
          '';
        };

        subUid = mkOption {
          type = types.int;
          description = "The id of the subuser that was allocated on the hetzner server for this backup.";
        };

        path = mkOption {
          type = types.str;
          description = ''
            The remote path to backup into. While not technically required for restic
            (since the subuser is chrooted on the remote), it is required for the
            automatic setup script that creates the users.
          '';
        };

        sshAgeSecret = mkOption {
          type = types.str;
          description = "The name of the agenix secret containing the ssh private key for accesing the storage box.";
        };
      };

      config = let
        subuser = "${submod.config.hetznerStorageBox.mainUser}-sub${toString submod.config.hetznerStorageBox.subUid}";
        url = "${subuser}@${submod.config.hetznerStorageBox.mainUser}.your-storagebox.de";
      in
        mkIf submod.config.hetznerStorageBox.enable {
          repository = "rclone:";
          extraOptions = [
            "rclone.program='ssh -p23 ${url} -i ${config.age.secrets.${submod.config.hetznerStorageBox.sshAgeSecret}.path}'"
          ];
        };
    }));
  };

  config.services.openssh.knownHosts.hetzner-storage-boxes = let
    hetznerStorageBoxHostnames =
      unique (flatten (flip mapAttrsToList config.services.restic.backups
          (_: backupCfg: optional backupCfg.hetznerStorageBox.enable "[${backupCfg.hetznerStorageBox.mainUser}.your-storagebox.de]:23")));
  in
    mkIf (hetznerStorageBoxHostnames != []) {
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICf9svRenC/PLKIL9nk6K/pxQgoiFC41wTNvoIncOxs";
      hostNames = hetznerStorageBoxHostnames;
    };
}
