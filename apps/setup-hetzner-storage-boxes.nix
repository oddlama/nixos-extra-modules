{
  pkgs,
  nixosConfigurations,
  decryptIdentity,
}: let
  inherit
    (pkgs.lib)
    attrValues
    concatLines
    concatStringsSep
    escapeShellArg
    filterAttrs
    flatten
    flip
    forEach
    getExe
    groupBy
    head
    length
    mapAttrs
    mapAttrsToList
    optional
    throwIf
    unique
    ;

  allBoxDefinitions = flatten (
    forEach (attrValues nixosConfigurations) (
      hostCfg:
        forEach (attrValues hostCfg.config.services.restic.backups) (
          backupCfg:
            optional backupCfg.hetznerStorageBox.enable (
              backupCfg.hetznerStorageBox
              // {sshPrivateKeyFile = hostCfg.config.age.secrets.${backupCfg.hetznerStorageBox.sshAgeSecret}.rekeyFile;}
            )
        )
    )
  );

  subUserFor = box: "${box.mainUser}-sub${toString box.subUid}";
  boxesBySubuser = groupBy subUserFor allBoxDefinitions;

  # We need to know the main storage box user to create subusers
  boxSubuserToMainUser =
    flip mapAttrs boxesBySubuser (_: boxes:
      head (unique (forEach boxes (box: box.mainUser))));

  boxSubuserToPrivateKeys =
    flip mapAttrs boxesBySubuser (_: boxes:
      unique (forEach boxes (box: box.sshPrivateKeyFile)));

  # Any subuid that has more than one path in use
  boxSubuserToPaths =
    flip mapAttrs boxesBySubuser (_: boxes:
      unique (forEach boxes (box: box.path)));

  duplicates = filterAttrs (_: boxes: length boxes > 1) boxSubuserToPaths;

  # Only one path must remain per subuser.
  boxSubuserToPath = throwIf (duplicates != {}) ''
    At least one storage box subuser has multiple paths assigned to it:
    ${concatStringsSep "\n" (mapAttrsToList (n: v: "${n}: ${toString v}") duplicates)}
  '' (mapAttrs (_: head) boxSubuserToPaths);

  authorizeResticCommand = privateKey: ''
    (
      echo -n 'command="rclone serve restic --stdio --append-only ./repo" '
      PATH="$PATH:${pkgs.age-plugin-yubikey}/bin" ${pkgs.rage}/bin/rage -d -i ${decryptIdentity} ${escapeShellArg privateKey} \
        | (exec 3<&0; ssh-keygen -f /proc/self/fd/3 -y)
    ) >> "$TMPFILE"
  '';

  setupSubuser = subuser: privateKeys: let
    mainUser = boxSubuserToMainUser.${subuser};
    path = boxSubuserToPath.${subuser};
  in ''
    echo "${mainUser} (for ${subuser}): Removing old ${path}/.ssh if it exists"
    # Remove any .ssh folder if it exists
    ${pkgs.openssh}/bin/ssh -p 23 "${mainUser}@${mainUser}.your-storagebox.de" -- rm -r ./${path}/.ssh &>/dev/null || true
    echo "${mainUser} (for ${subuser}): Creating ${path}/.ssh"
    # Create subuser directory and .ssh
    ${pkgs.openssh}/bin/ssh -p 23 "${mainUser}@${mainUser}.your-storagebox.de" -- mkdir -p ./${path}/.ssh
    # Create repo directory
    ${pkgs.openssh}/bin/ssh -p 23 "${mainUser}@${mainUser}.your-storagebox.de" -- mkdir -p ./${path}/repo

    # Derive and upload all authorized keys
    TMPFILE=$(mktemp)
    ${concatLines (map authorizeResticCommand privateKeys)}
    echo "${mainUser} (for ${subuser}): Uploading $(wc -l < "$TMPFILE") authorized_keys"
    ${pkgs.openssh}/bin/scp -P 23 "$TMPFILE" "${mainUser}@${mainUser}.your-storagebox.de":./${path}/.ssh/authorized_keys
    rm "$TMPFILE"
  '';
in {
  type = "app";
  program = getExe (pkgs.writeShellApplication {
    name = "setup-hetzner-storage-boxes";
    text = ''
      set -euo pipefail

      ${concatLines (mapAttrsToList setupSubuser boxSubuserToPrivateKeys)}

      echo
      echo "[33mPlease visit https://robot.hetzner.com/storage and make sure"
      echo "that the following subusers are setup correctly:[m"
      ${concatLines (mapAttrsToList (u: p: "echo '[33m  ${u}: ${p}[m'") boxSubuserToPath)}
    '';
  });
}
