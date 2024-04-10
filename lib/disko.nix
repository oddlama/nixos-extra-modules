_inputs: final: prev: {
  lib =
    prev.lib
    // {
      disko = {
        content = {
          luksZfs = luksName: pool: {
            type = "luks";
            name = "${pool}_${luksName}";
            settings.allowDiscards = true;
            content = {
              type = "zfs";
              inherit pool;
            };
          };
        };
        gpt = rec {
          partGrub = {
            priority = 1;
            size = "1M";
            type = "ef02";
          };
          partEfi = size: {
            inherit size;
            priority = 1000;
            type = "ef00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          partBoot = size:
            partEfi size
            // {
              hybrid.mbrBootableFlag = true;
            };
          partSwap = size: {
            inherit size;
            priority = 2000;
            content = {
              type = "swap";
              randomEncryption = true;
            };
          };
          partLuksZfs = luksName: pool: size: {
            inherit size;
            content = final.lib.disko.content.luksZfs luksName pool;
          };
        };
        zfs = rec {
          mkZpool = prev.lib.recursiveUpdate {
            type = "zpool";
            rootFsOptions = {
              compression = "zstd";
              acltype = "posix";
              atime = "off";
              xattr = "sa";
              dnodesize = "auto";
              mountpoint = "none";
              canmount = "off";
              devices = "off";
            };
            options.ashift = "12";
          };

          impermanenceZfsDatasets = {
            "local" = unmountable;
            "local/root" =
              filesystem "/"
              // {
                postCreateHook = "zfs snapshot rpool/local/root@blank";
              };
            "local/nix" = filesystem "/nix";
            "local/state" = filesystem "/state";
            "safe" = unmountable;
            "safe/persist" = filesystem "/persist";
          };

          unmountable = {type = "zfs_fs";};
          filesystem = mountpoint: {
            type = "zfs_fs";
            options = {
              canmount = "noauto";
              inherit mountpoint;
            };
            # Required to add dependencies for initrd
            inherit mountpoint;
          };
        };
      };
    };
}
