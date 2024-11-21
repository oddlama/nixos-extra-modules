{
  config,
  inputs,
  lib,
  ...
}: let
  inherit
    (lib)
    any
    attrNames
    attrValues
    concatAttrs
    concatMap
    concatMapStrings
    concatStringsSep
    duplicates
    filter
    flip
    head
    listToAttrs
    mapAttrsToList
    mergeToplevelConfigs
    mkIf
    mkOption
    nameValuePair
    net
    optionalAttrs
    optionals
    stringLength
    types
    ;

  cfg = config.wireguard;
  nodeName = config.node.name;

  configForNetwork = wgName: wgCfg: let
    inherit
      (lib.wireguard.getNetwork inputs wgName)
      externalPeerName
      externalPeerNamesRaw
      networkCidrs
      participatingClientNodes
      participatingNodes
      participatingServerNodes
      peerPresharedKeyPath
      peerPresharedKeySecret
      peerPrivateKeyPath
      peerPrivateKeySecret
      peerPublicKeyPath
      toNetworkAddr
      usedAddresses
      wgCfgOf
      ;

    isServer = wgCfg.server.host != null;
    isClient = wgCfg.client.via != null;
    filterSelf = filter (x: x != nodeName);

    # All nodes that use our node as the via into the wireguard network
    ourClientNodes =
      optionals isServer
      (filter (n: (wgCfgOf n).client.via == nodeName) participatingClientNodes);

    # The list of peers for which we have to know the psk.
    neededPeers =
      if isServer
      then
        # Other servers in the same network
        filterSelf participatingServerNodes
        # Our external peers
        ++ map externalPeerName (attrNames wgCfg.server.externalPeers)
        # Our clients
        ++ ourClientNodes
      else [wgCfg.client.via];

    # Figure out if there are duplicate peers or addresses so we can
    # make an assertion later.
    duplicatePeers = duplicates externalPeerNamesRaw;
    duplicateAddrs = duplicates usedAddresses;

    # Adds context information to the assertions for this network
    assertionPrefix = "Wireguard network '${wgName}' on '${nodeName}'";

    # Calculates the allowed ips for another server from our perspective.
    # Usually we just want to allow other peers to route traffic
    # for our "children" through us, additional to traffic to us of course.
    # If a server exposes additional network access (global, lan, ...),
    # these can be added aswell.
    # TODO (do that)
    serverAllowedIPs = serverNode: let
      snCfg = wgCfgOf serverNode;
    in
      map (net.cidr.make 128) (
        # The server accepts traffic to it's own address
        snCfg.addresses
        # plus traffic for any of its external peers
        ++ attrValues snCfg.server.externalPeers
        # plus traffic for any client that is connected via that server
        ++ concatMap (n: (wgCfgOf n).addresses) (filter (n: (wgCfgOf n).client.via == serverNode) participatingClientNodes)
      );
  in {
    assertions = [
      {
        assertion = any (n: (wgCfgOf n).server.host != null) participatingNodes;
        message = "${assertionPrefix}: At least one node in a network must be a server.";
      }
      {
        assertion = duplicatePeers == [];
        message = "${assertionPrefix}: Multiple definitions for external peer(s):${concatMapStrings (x: " '${x}'") duplicatePeers}";
      }
      {
        assertion = duplicateAddrs == [];
        message = "${assertionPrefix}: Addresses used multiple times: ${concatStringsSep ", " duplicateAddrs}";
      }
      {
        assertion = isServer != isClient;
        message = "${assertionPrefix}: A node must either be a server (define server.host) or a client (define client.via).";
      }
      {
        assertion = isClient -> ((wgCfgOf wgCfg.client.via).server.host != null);
        message = "${assertionPrefix}: The specified via node '${wgCfg.client.via}' must be a wireguard server.";
      }
      {
        assertion = stringLength wgCfg.linkName < 16;
        message = "${assertionPrefix}: The specified linkName '${wgCfg.linkName}' is too long (must be max 15 characters).";
      }
    ];

    # Open the udp port for the wireguard endpoint in the firewall
    networking.firewall.allowedUDPPorts = mkIf (isServer && wgCfg.server.openFirewall) [wgCfg.server.port];

    # If requested, create firewall rules for the network / specific participants and open ports.
    networking.nftables.firewall = let
      inherit (config.networking.nftables.firewall) localZoneName;
    in {
      zones =
        {
          # Parent zone for the whole interface
          "wg-${wgCfg.linkName}".interfaces = [wgCfg.linkName];
        }
        // listToAttrs (flip map participatingNodes (
          peer: let
            peerCfg = wgCfgOf peer;
          in
            # Subzone to specifically target the peer
            nameValuePair "wg-${wgCfg.linkName}-node-${peer}" {
              parent = "wg-${wgCfg.linkName}";
              ipv4Addresses = [peerCfg.ipv4];
              ipv6Addresses = [peerCfg.ipv6];
            }
        ));

      rules =
        {
          # Open ports for whole network
          "wg-${wgCfg.linkName}-to-${localZoneName}" = {
            from = ["wg-${wgCfg.linkName}"];
            to = [localZoneName];
            ignoreEmptyRule = true;

            inherit
              (wgCfg.firewallRuleForAll)
              allowedTCPPorts
              allowedUDPPorts
              ;
          };
        }
        # Open ports for specific nodes network
        // listToAttrs (flip map participatingNodes (
          peer:
            nameValuePair "wg-${wgCfg.linkName}-node-${peer}-to-${localZoneName}" (
              mkIf (wgCfg.firewallRuleForNode ? ${peer}) {
                from = ["wg-${wgCfg.linkName}-node-${peer}"];
                to = [localZoneName];
                ignoreEmptyRule = true;

                inherit
                  (wgCfg.firewallRuleForNode.${peer})
                  allowedTCPPorts
                  allowedUDPPorts
                  ;
              }
            )
        ));
    };

    age.secrets =
      concatAttrs (map
        (other: {
          ${peerPresharedKeySecret nodeName other} = {
            rekeyFile = peerPresharedKeyPath nodeName other;
            owner = "systemd-network";
            generator.script = {pkgs, ...}: "${pkgs.wireguard-tools}/bin/wg genpsk";
          };
        })
        neededPeers)
      // {
        ${peerPrivateKeySecret nodeName} = {
          rekeyFile = peerPrivateKeyPath nodeName;
          owner = "systemd-network";
          generator.script = {
            pkgs,
            file,
            ...
          }: ''
            priv=$(${pkgs.wireguard-tools}/bin/wg genkey)
            ${pkgs.wireguard-tools}/bin/wg pubkey <<< "$priv" > ${lib.escapeShellArg (lib.removeSuffix ".age" file + ".pub")}
            echo "$priv"
          '';
        };
      };

    systemd.network.netdevs."${wgCfg.unitConfName}" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = wgCfg.linkName;
        Description = "Wireguard network ${wgName}";
      };
      wireguardConfig =
        {
          PrivateKeyFile = config.age.secrets.${peerPrivateKeySecret nodeName}.path;
        }
        // optionalAttrs isServer {
          ListenPort = wgCfg.server.port;
        };
      wireguardPeers =
        if isServer
        then
          # Always include all other server nodes.
          map (serverNode: let
            snCfg = wgCfgOf serverNode;
          in {
            PublicKey = builtins.readFile (peerPublicKeyPath serverNode);
            PresharedKeyFile = config.age.secrets.${peerPresharedKeySecret nodeName serverNode}.path;
            AllowedIPs = serverAllowedIPs serverNode;
            Endpoint = "${snCfg.server.host}:${toString snCfg.server.port}";
          })
          (filterSelf participatingServerNodes)
          # All our external peers
          ++ mapAttrsToList (extPeer: ips: let
            peerName = externalPeerName extPeer;
          in {
            PublicKey = builtins.readFile (peerPublicKeyPath peerName);
            PresharedKeyFile = config.age.secrets.${peerPresharedKeySecret nodeName peerName}.path;
            AllowedIPs = map (net.cidr.make 128) ips;
            # Connections to external peers should always be kept alive
            PersistentKeepalive = 25;
          })
          wgCfg.server.externalPeers
          # All client nodes that have their via set to us.
          ++ map (clientNode: let
            clientCfg = wgCfgOf clientNode;
          in {
            PublicKey = builtins.readFile (peerPublicKeyPath clientNode);
            PresharedKeyFile = config.age.secrets.${peerPresharedKeySecret nodeName clientNode}.path;
            AllowedIPs = map (net.cidr.make 128) clientCfg.addresses;
          })
          ourClientNodes
        else
          # We are a client node, so only include our via server.
          [
            (
              let
                snCfg = wgCfgOf wgCfg.client.via;
              in
                {
                  PublicKey = builtins.readFile (peerPublicKeyPath wgCfg.client.via);
                  PresharedKeyFile = config.age.secrets.${peerPresharedKeySecret nodeName wgCfg.client.via}.path;
                  Endpoint = "${snCfg.server.host}:${toString snCfg.server.port}";
                  # Access to the whole network is routed through our entry node.
                  AllowedIPs = networkCidrs;
                }
                // optionalAttrs wgCfg.client.keepalive {
                  PersistentKeepalive = 25;
                }
            )
          ];
    };

    systemd.network.networks.${wgCfg.unitConfName} = {
      matchConfig.Name = wgCfg.linkName;
      address = map toNetworkAddr wgCfg.addresses;
    };
  };
in {
  options.wireguard = mkOption {
    default = {};
    description = "Configures wireguard networks via systemd-networkd.";
    type = types.lazyAttrsOf (types.submodule ({
      config,
      name,
      options,
      ...
    }: {
      options = {
        server = {
          host = mkOption {
            default = null;
            type = types.nullOr types.str;
            description = "The hostname or ip address which other peers can use to reach this host. No server functionality will be activated if set to null.";
          };

          port = mkOption {
            default = 51820;
            type = types.port;
            description = "The port to listen on.";
          };

          openFirewall = mkOption {
            default = false;
            type = types.bool;
            description = "Whether to open the firewall for the specified {option}`port`.";
          };

          externalPeers = mkOption {
            type = types.attrsOf (types.listOf (types.net.ip-in config.addresses));
            default = {};
            example = {my-android-phone = ["10.0.0.97"];};
            description = ''
              Allows defining an extra set of peers that should be added to this wireguard network,
              but will not be managed by this flake. (e.g. phones)

              These external peers will only know this node as a peer, which will forward
              their traffic to other members of the network if required. This requires
              this node to act as a server.
            '';
          };

          reservedAddresses = mkOption {
            type = types.listOf types.net.cidr;
            default = [];
            example = ["10.0.0.0/24" "fd00:cafe::/64"];
            description = ''
              Allows defining extra CIDR network ranges that shall be reserved for this network.
              Reservation means that those address spaces will be guaranteed to be included in
              the spanned network, but no rules will be enforced as to who in the network may use them.

              By default, this module will try to allocate the smallest address space that includes
              all network peers. If you know that there might be additional external peers added later,
              it may be beneficial to reserve a bigger address space from the start to avoid having
              to update existing external peers when the generated address space expands.
            '';
          };
        };

        client = {
          via = mkOption {
            default = null;
            type = types.nullOr types.str;
            description = ''
              The server node via which to connect to the network.
              No client functionality will be activated if set to null.
            '';
          };

          keepalive = mkOption {
            default = true;
            type = types.bool;
            description = "Whether to keep this connection alive using PersistentKeepalive. Set to false only for networks where client and server IPs are stable.";
          };
        };

        priority = mkOption {
          default = 40;
          type = types.int;
          description = "The order priority used when creating systemd netdev and network files.";
        };

        linkName = mkOption {
          default = name;
          type = types.str;
          description = "The name for the created network interface.";
        };

        unitConfName = mkOption {
          default = "${toString config.priority}-${config.linkName}";
          readOnly = true;
          type = types.str;
          description = ''
            The name used for unit configuration files. This is a read-only option.
            Access this if you want to add additional settings to the generated systemd units.
          '';
        };

        ipv4 = mkOption {
          type = types.lazyOf types.net.ipv4;
          default = types.lazyValue (lib.wireguard.getNetwork inputs name).assignedIpv4Addresses.${nodeName};
          description = ''
            The ipv4 address for this machine. If you do not set this explicitly,
            a semi-stable ipv4 address will be derived automatically based on the
            hostname of this machine. At least one participating server must reserve
            a big-enough space of addresses by setting `reservedAddresses`.
            See `net.cidr.assignIps` for more information on the algorithm.
          '';
        };

        ipv6 = mkOption {
          type = types.lazyOf types.net.ipv6;
          default = types.lazyValue (lib.wireguard.getNetwork inputs name).assignedIpv6Addresses.${nodeName};
          description = ''
            The ipv6 address for this machine. If you do not set this explicitly,
            a semi-stable ipv6 address will be derived automatically based on the
            hostname of this machine. At least one participating server must reserve
            a big-enough space of addresses by setting `reservedAddresses`.
            See `net.cidr.assignIps` for more information on the algorithm.
          '';
        };

        addresses = mkOption {
          type = types.listOf (types.lazyOf types.net.ip);
          default = [
            (head options.ipv4.definitions)
            (head options.ipv6.definitions)
          ];
          description = ''
            The ip addresses (v4 and/or v6) to use for this machine.
            The actual network cidr will automatically be derived from all network participants.
            By default this will just include {option}`ipv4` and {option}`ipv6` as configured.
          '';
        };

        firewallRuleForAll = mkOption {
          default = {};
          description = ''
            Allows you to set specific firewall rules for traffic originating from any participant in this
            wireguard network. A corresponding rule `wg-<network-name>-to-<local-zone-name>` will be created to easily expose
            services to the network.
          '';
          type = types.submodule {
            options = {
              allowedTCPPorts = mkOption {
                type = types.listOf types.port;
                default = [];
                description = "Convenience option to open specific TCP ports for traffic from the network.";
              };
              allowedUDPPorts = mkOption {
                type = types.listOf types.port;
                default = [];
                description = "Convenience option to open specific UDP ports for traffic from the network.";
              };
            };
          };
        };

        firewallRuleForNode = mkOption {
          default = {};
          description = ''
            Allows you to set specific firewall rules just for traffic originating from another network node.
            A corresponding rule `wg-<network-name>-node-<node-name>-to-<local-zone-name>` will be created to easily expose
            services to that node.
          '';
          type = types.attrsOf (types.submodule {
            options = {
              allowedTCPPorts = mkOption {
                type = types.listOf types.port;
                default = [];
                description = "Convenience option to open specific TCP ports for traffic from another node.";
              };
              allowedUDPPorts = mkOption {
                type = types.listOf types.port;
                default = [];
                description = "Convenience option to open specific UDP ports for traffic from another node.";
              };
            };
          });
        };
      };
    }));
  };

  config = mkIf (cfg != {}) (mergeToplevelConfigs
    ["assertions" "age" "networking" "systemd"]
    (mapAttrsToList configForNetwork cfg));
}
