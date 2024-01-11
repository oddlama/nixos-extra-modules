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
        gpt = {
          partGrub = name: start: end: {
            inherit name start end;
            part-type = "primary";
            flags = ["bios_grub"];
          };
          partEfi = name: start: end: {
            inherit name start end;
            fs-type = "fat32";
            bootable = true;
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          partSwap = name: start: end: {
            inherit name start end;
            fs-type = "linux-swap";
            content = {
              type = "swap";
              randomEncryption = true;
            };
          };
          partLuksZfs = luksName: pool: start: end: {
            inherit start end;
            name = "${pool}_${luksName}";
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
