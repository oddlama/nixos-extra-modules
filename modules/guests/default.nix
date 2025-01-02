{
  config,
  lib,
  pkgs,
  utils,
  ...
} @ attrs: let
  inherit
    (lib)
    attrNames
    attrValues
    attrsToList
    length
    splitString
    elemAt
    disko
    escapeShellArg
    flatten
    flip
    foldl'
    forEach
    groupBy
    hasInfix
    hasPrefix
    listToAttrs
    literalExpression
    makeBinPath
    mapAttrs
    mapAttrsToList
    mergeToplevelConfigs
    mkIf
    mkMerge
    mkOption
    net
    optional
    optionalAttrs
    types
    warnIf
    ;

  # All available backends
  backends = [
    "microvm"
    "container"
  ];

  guestsByBackend =
    lib.genAttrs backends (_: {})
    // mapAttrs (_: listToAttrs) (groupBy (x: x.value.backend) (attrsToList config.guests));

  # List the necessary mount units for the given guest
  fsMountUnitsFor = guestCfg: map (x: "${utils.escapeSystemdPath x.hostMountpoint}.mount") (attrValues guestCfg.zfs);

  # Configuration required on the host for a specific guest
  defineGuest = _guestName: guestCfg: {
    # Add the required datasets to the disko configuration of the machine
    disko.devices.zpool = mkMerge (
      flip map (attrValues guestCfg.zfs) (zfsCfg: {
        ${zfsCfg.pool}.datasets.${zfsCfg.dataset} =
          # We generate the mountpoint fileSystems entries ourselfs to enable shared folders between guests
          disko.zfs.unmountable;
      })
    );

    # Ensure that the zfs dataset exists before it is mounted.
    systemd.services = mkMerge (
      flip map (attrValues guestCfg.zfs) (
        zfsCfg: let
          fsMountUnit = "${utils.escapeSystemdPath zfsCfg.hostMountpoint}.mount";
        in {
          "zfs-ensure-${utils.escapeSystemdPath "${zfsCfg.pool}/${zfsCfg.dataset}"}" = {
            wantedBy = [fsMountUnit];
            before = [fsMountUnit];
            after = [
              "zfs-import-${utils.escapeSystemdPath zfsCfg.pool}.service"
              "zfs-mount.target"
            ];
            unitConfig.DefaultDependencies = "no";
            serviceConfig.Type = "oneshot";
            script = let
              poolDataset = "${zfsCfg.pool}/${zfsCfg.dataset}";
              diskoDataset = config.disko.devices.zpool.${zfsCfg.pool}.datasets.${zfsCfg.dataset};
            in ''
              export PATH=${makeBinPath [pkgs.zfs]}":$PATH"
              if ! zfs list -H -o type ${escapeShellArg poolDataset} &>/dev/null ; then
                ${diskoDataset._create}
              fi
            '';
          };
        }
      )
    );
  };

  defineMicrovm = guestName: guestCfg: {
    # Ensure that the zfs dataset exists before it is mounted.
    systemd.services."microvm@${guestName}" = {
      requires = fsMountUnitsFor guestCfg;
      after = fsMountUnitsFor guestCfg;
    };

    microvm.vms.${guestName} = import ./microvm.nix guestName guestCfg attrs;
  };

  defineContainer = guestName: guestCfg: {
    # Ensure that the zfs dataset exists before it is mounted.
    systemd.services."container@${guestName}" = {
      requires = fsMountUnitsFor guestCfg;
      after = fsMountUnitsFor guestCfg;
      # Don't use the notify service type. Using exec will always consider containers
      # started immediately and donesn't wait until the container is fully booted.
      # Containers should behave like independent machines, and issues inside the container
      # will unnecessarily lock up the service on the host otherwise.
      # This causes issues on system activation or when containers take longer to start
      # than TimeoutStartSec.
      serviceConfig.Type = lib.mkForce "exec";
    };

    containers.${guestName} = import ./container.nix guestName guestCfg attrs;
  };
in {
  imports = [
    {
      # This is opt-out, so we can't put this into the mkIf below
      microvm.host.enable = guestsByBackend.microvm != {};
    }
  ];

  options.node.type = mkOption {
    type = types.enum (["host"] ++ backends);
    description = "The type of this machine.";
    default = "host";
  };

  options.containers = mkOption {
    type = types.attrsOf (
      types.submodule (submod: {
        options.nixosConfiguration = mkOption {
          type = types.unspecified;
          default = null;
          description = "Set this to the result of a `nixosSystem` invocation to use it as the guest system. This will set the `path` option for you.";
        };
        config = mkIf (submod.config.nixosConfiguration != null) (
          {
            path = submod.config.nixosConfiguration.config.system.build.toplevel;
          }
          // optionalAttrs (config ? topology) {
            _nix_topology_config = submod.config.nixosConfiguration.config;
          }
        );
      })
    );
  };

  options.guests = mkOption {
    default = {};
    description = "Defines the actual vms and handles the necessary base setup for them.";
    type = types.attrsOf (
      types.submodule (submod: {
        options = {
          nodeName = mkOption {
            type = types.str;
            default = "${config.node.name}-${submod.config._module.args.name}";
            description = ''
              The name of the resulting node. By default this will be a compound name
              of the host's name and the guest's name to avoid name clashes. Can be
              overwritten to designate special names to specific guests.
            '';
          };

          backend = mkOption {
            type = types.enum backends;
            description = ''
              Determines how the guest will be hosted. You can currently choose
              between microvm based deployment, or nixos containers.
            '';
          };

          extraSpecialArgs = mkOption {
            type = types.attrs;
            default = {};
            example = literalExpression "{ inherit inputs; }";
            description = ''
              Extra `specialArgs` passed to each guest system definition. This
              option can be used to pass additional arguments to all modules.
            '';
          };

          # Options for the microvm backend
          microvm = {
            system = mkOption {
              type = types.str;
              description = "The system that this microvm should use";
            };

            baseMac = mkOption {
              type = types.net.mac;
              description = "The base mac address from which the guest's mac will be derived. Only the second and third byte are used, so for 02:XX:YY:ZZ:ZZ:ZZ, this specifies XX and YY, while Zs are generated automatically. Not used if the mac is set directly.";
              default = "02:01:27:00:00:00";
            };
            interfaces = mkOption {
              description = "An attrset correlating the host interface to which the microvm should be attached via macvtap, with its mac address";
              type = types.attrsOf (
                types.submodule (submod-iface: {
                  options = {
                    hostLink = mkOption {
                      type = types.str;
                      description = "The name of the host side link to which this interface will bind.";
                      default = submod-iface.config._module.args.name;
                      example = "lan";
                    };
                    mac = mkOption {
                      type = types.net.mac;
                      description = "The MAC address for the guest's macvtap interface";
                      default = let
                        base = "02:${lib.substring 3 5 submod.config.microvm.baseMac}:00:00:00";
                      in
                        (net.mac.assignMacs base 24 [] (
                          flatten (
                            flip mapAttrsToList config.guests (
                              name: value: forEach (attrNames value.microvm.interfaces) (iface: "${name}-${iface}")
                            )
                          )
                        ))
                        ."${submod.config._module.args.name}-${submod-iface.config._module.args.name}";
                    };
                  };
                })
              );
              default = {};
            };
          };

          # Options for the container backend
          container = {
            macvlans = mkOption {
              type = types.listOf types.str;
              description = ''
                The macvlans to be created for the container.
                Can be either an interface name in which case the container interface will be called mv-<name> or a pair
                of <host iface name>:<container iface name>.
              '';
            };
          };

          networking.links = mkOption {
            type = types.listOf types.str;
            description = "The ethernet links inside of the guest. For containers, these cannot be named similar to an existing interface on the host.";
            default =
              if submod.config.backend == "microvm"
              then (flip mapAttrsToList submod.config.microvm.interfaces (name: _: name))
              else if submod.config.backend == "container"
              then
                (forEach submod.config.container.macvlans (
                  name: let
                    split = splitString ":" name;
                  in
                    if length split > 1
                    then elemAt split 1
                    else "mv-${name}"
                ))
              else throw "Invalid backend";
          };

          zfs = mkOption {
            description = "zfs datasets to mount into the guest";
            default = {};
            type = types.attrsOf (
              types.submodule (zfsSubmod: {
                options = {
                  pool = mkOption {
                    type = types.str;
                    description = "The host's zfs pool on which the dataset resides";
                  };

                  dataset = mkOption {
                    type = types.str;
                    example = "safe/guests/mycontainer";
                    description = "The host's dataset that should be used for this mountpoint (will automatically be created, including parent datasets)";
                  };

                  hostMountpoint = mkOption {
                    type = types.path;
                    default = "/guests/${submod.config._module.args.name}${zfsSubmod.config.guestMountpoint}";
                    example = "/guests/mycontainer/persist";
                    description = "The host's mountpoint for the guest's dataset";
                  };

                  guestMountpoint = mkOption {
                    type = types.path;
                    default = zfsSubmod.config._module.args.name;
                    example = "/persist";
                    description = "The mountpoint inside the guest.";
                  };
                };
              })
            );
          };

          autostart = mkOption {
            type = types.bool;
            default = false;
            description = "Whether this guest should be started automatically with the host";
          };

          modules = mkOption {
            type = types.listOf types.unspecified;
            default = [];
            description = "Additional modules to load";
          };
        };
      })
    );
  };

  config = mkIf (config.guests != {}) (mkMerge [
    {
      systemd.tmpfiles.rules = [
        "d /guests 0700 root root -"
      ];

      # To enable shared folders we need to do all fileSystems entries ourselfs
      fileSystems = let
        zfsDefs = flatten (
          flip mapAttrsToList config.guests (
            _: guestCfg:
              flip mapAttrsToList guestCfg.zfs (
                _: zfsCfg: {
                  path = "${zfsCfg.pool}/${zfsCfg.dataset}";
                  inherit (zfsCfg) hostMountpoint;
                }
              )
          )
        );
        # Due to limitations in zfs mounting we need to explicitly set an order in which
        # any dataset gets mounted
        zfsDefsByPath = flip groupBy zfsDefs (x: x.path);
      in
        mkMerge (
          flip mapAttrsToList zfsDefsByPath (
            _: defs:
              (
                foldl'
                (
                  {
                    prev,
                    res,
                  }: elem: {
                    prev = elem;
                    res =
                      res
                      // {
                        ${elem.hostMountpoint} = {
                          fsType = "zfs";
                          options =
                            ["zfsutil"]
                            ++ optional (prev != null)
                            "x-systemd.requires-mounts-for=${
                              warnIf (hasInfix " " prev.hostMountpoint)
                              "HostMountpoint ${prev.hostMountpoint} cannot contain a space"
                              prev.hostMountpoint
                            }";
                          device = elem.path;
                        };
                      };
                  }
                )
                {
                  prev = null;
                  res = {};
                }
                defs
              )
              .res
          )
        );

      assertions = flatten (
        flip mapAttrsToList config.guests (
          guestName: guestCfg:
            flip mapAttrsToList guestCfg.zfs (
              zfsName: zfsCfg: {
                assertion = hasPrefix "/" zfsCfg.guestMountpoint;
                message = "guest ${guestName}: zfs ${zfsName}: the guestMountpoint must be an absolute path.";
              }
            )
        )
      );
    }
    (mergeToplevelConfigs ["disko" "systemd" "fileSystems"] (
      mapAttrsToList defineGuest config.guests
    ))
    (mergeToplevelConfigs ["containers" "systemd"] (
      mapAttrsToList defineContainer guestsByBackend.container
    ))
    (mergeToplevelConfigs ["microvm" "systemd"] (
      mapAttrsToList defineMicrovm guestsByBackend.microvm
    ))
  ]);
}
