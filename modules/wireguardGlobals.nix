{ lib, ... }:
let
  inherit (lib)
    mkOption
    types
    importJSON
    ;
in
{
  options.globals = mkOption {
    type = types.submodule {
      options = {
        wireguard = mkOption {
          default = { };
          type = types.attrsOf (
            types.submodule (
              { name, config, ... }:
              let
                wgConf = config;
                wgName = name;
              in
              {
                options = {
                  host = mkOption {
                    type = types.str;
                    description = "The host name or IP addresse for reaching the server node.";
                  };
                  idFile = mkOption {
                    type = types.nullOr types.path;
                    default = null;
                    description = "A json file containing a mapping from hostname to id.";
                  };
                  cidrv4 = mkOption {
                    type = types.nullOr types.net.cidrv4;
                    default = null;
                    description = "The server host of this wireguard";
                  };
                  cidrv6 = mkOption {
                    type = types.nullOr types.net.cidrv6;
                    default = null;
                    description = "The server host of this wireguard";
                  };
                  port = mkOption {
                    default = 51820;
                    type = types.port;
                    description = "The port the server listens on";
                  };
                  openFirewall = mkOption {
                    default = false;
                    type = types.bool;
                    description = "Whether to open the servers firewall for the specified {option}`port`. Has no effect for client nodes.";
                  };

                  hosts = mkOption {
                    default = { };
                    description = "Attrset of hostName to host specific config";
                    type = types.attrsOf (
                      types.submodule (
                        { config, name, ... }:
                        {
                          config.id =
                            let
                              inherit (wgConf) idFile;
                            in
                            if (idFile == null) then
                              null
                            else
                              (
                                let
                                  conf = importJSON idFile;
                                in
                                conf.${name} or null
                              );
                          options = {
                            server = mkOption {
                              default = false;
                              type = types.bool;
                              description = "Whether this host acts as the server and relay for the network.  Has to be set for exactly 1 host.";
                            };
                            linkName = mkOption {
                              default = wgName;
                              type = types.str;
                              description = "The name of the created network interface. Has to be less than 15 characters.";
                            };
                            unitConfName = mkOption {
                              default = "40-${config.linkName}";
                              type = types.str;
                              description = "The name of the generated systemd unit configuration files.";
                              readOnly = true;
                            };
                            id = mkOption {
                              type = types.int;
                              description = "The unique id of this host. Used to derive its IP addresses. Has to be smaller than the size of the Subnet.";
                            };
                            ipv4 = mkOption {
                              type = types.nullOr types.net.ipv4;
                              default = if (wgConf.cidrv4 == null) then null else lib.net.cidr.host config.id wgConf.cidrv4;
                              readOnly = true;
                              description = "The IPv4 of this host. Automatically computed from the {option}`id`";
                            };
                            ipv6 = mkOption {
                              type = types.nullOr types.net.ipv6;
                              default = if (wgConf.cidrv4 == null) then null else lib.net.cidr.host config.id wgConf.cidrv6;
                              readOnly = true;
                              description = "The IPv4 of this host. Automatically computed from the {option}`id`";
                            };
                            keepalive = mkOption {
                              default = true;
                              type = types.bool;
                              description = "Whether to keep the connection alive using PersistentKeepalive. Has no effect for server nodes.";
                            };
                            firewallRuleForAll = mkOption {
                              default = { };
                              description = ''
                                Allows you to set specific firewall rules for traffic originating from any participant in this
                                wireguard network. A corresponding rule `wg-<network-name>-to-<local-zone-name>` will be created to easily expose
                                services to the network.
                              '';
                              type = types.submodule {
                                options = {
                                  allowedTCPPorts = mkOption {
                                    type = types.listOf types.port;
                                    default = [ ];
                                    description = "Convenience option to open specific TCP ports for traffic from the network.";
                                  };
                                  allowedUDPPorts = mkOption {
                                    type = types.listOf types.port;
                                    default = [ ];
                                    description = "Convenience option to open specific UDP ports for traffic from the network.";
                                  };
                                };
                              };
                            };
                            firewallRuleForNode = mkOption {
                              default = { };
                              description = ''
                                Allows you to set specific firewall rules just for traffic originating from another network node.
                                A corresponding rule `wg-<network-name>-node-<node-name>-to-<local-zone-name>` will be created to easily expose
                                services to that node.
                              '';
                              type = types.attrsOf (
                                types.submodule {
                                  options = {
                                    allowedTCPPorts = mkOption {
                                      type = types.listOf types.port;
                                      default = [ ];
                                      description = "Convenience option to open specific TCP ports for traffic from another node.";
                                    };
                                    allowedUDPPorts = mkOption {
                                      type = types.listOf types.port;
                                      default = [ ];
                                      description = "Convenience option to open specific UDP ports for traffic from another node.";
                                    };
                                  };
                                }
                              );
                            };
                          };
                        }
                      )
                    );
                  };
                };
              }
            )
          );
        };
      };
    };
  };
}
