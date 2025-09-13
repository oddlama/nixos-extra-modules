{
  config,
  inputs,
  lib,
  globals,
  ...
}:
let
  inherit (lib)
    any
    attrNames
    concatMapAttrs
    count
    mkMerge
    filterAttrs
    flip
    mapAttrs'
    mapAttrsToList
    mkIf
    nameValuePair
    attrValues
    net
    optional
    optionalAttrs
    stringLength
    concatLists
    ;

  memberWG = filterAttrs (
    _: cfg: any (x: x == config.node.name) (attrNames cfg.hosts)
  ) globals.wireguard;
in

{
  assertions = concatLists (
    flip mapAttrsToList memberWG (
      networkName: networkCfg:
      let
        assertionPrefix = "While evaluating the wireguard network ${networkName}:";
        hostCfg = networkCfg.hosts.${config.node.name};
      in
      [
        {
          assertion = networkCfg.cidrv4 != null || networkCfg.cidrv6 != null;
          message = "${assertionPrefix}: At least one of cidrv4 or cidrv6 has to be set.";
        }
        {
          assertion = (count (x: x.server) (attrValues networkCfg.hosts)) == 1;
          message = "${assertionPrefix}: You have to declare exactly 1 server node.";
        }
        {
          assertion = (count (x: x.id == hostCfg.id) (attrValues networkCfg.hosts)) == 1;
          message = "${assertionPrefix}: More than one host with id ${toString hostCfg.id}";
        }
        {
          assertion = stringLength hostCfg.linkName < 16;
          message = "${assertionPrefix}: The specified linkName '${hostCfg.linkName}' is too long (must be max 15 characters).";
        }
      ]
    )
  );
  networking.firewall.allowedUDPPorts = mkMerge (
    flip mapAttrsToList memberWG (
      _: networkCfg:
      let
        hostCfg = networkCfg.hosts.${config.node.name};
      in
      optional (hostCfg.server && networkCfg.openFirewall) networkCfg.port
    )
  );
  networking.nftables.firewall.zones = mkMerge (
    flip mapAttrsToList memberWG (
      _: networkCfg:
      let
        hostCfg = networkCfg.hosts.${config.node.name};
        peers = filterAttrs (name: _: name != config.node.name) networkCfg.hosts;
      in
      {
        # Parent zone for the whole network
        "wg-${hostCfg.linkName}".interfaces = [ hostCfg.linkName ];
      }
      // (flip mapAttrs' peers (
        name: cfg:
        nameValuePair "wg-${hostCfg.linkName}-node-${name}" {
          parent = "wg-${hostCfg.linkName}";
          ipv4Addresses = optional (cfg.ipv4 != null) cfg.ipv4;
          ipv6Addresses = optional (cfg.ipv6 != null) cfg.ipv6;
        }
      ))
    )
  );
  networking.nftables.firewall.rules = mkMerge (
    flip mapAttrsToList memberWG (
      _: networkCfg:
      let
        inherit (config.networking.nftables.firewall) localZoneName;
        hostCfg = networkCfg.hosts.${config.node.name};
        peers = filterAttrs (name: _: name != config.node.name) networkCfg.hosts;
      in
      {
        "wg-${hostCfg.linkName}-to-${localZoneName}" = {
          from = [ "wg-${hostCfg.linkName}" ];
          to = [ localZoneName ];
          ignoreEmptyRule = true;

          inherit (hostCfg.firewallRuleForAll)
            allowedTCPPorts
            allowedUDPPorts
            ;
        };
      }
      // (flip mapAttrs' peers (
        name: _:
        nameValuePair "wg-${hostCfg.linkName}-node-${name}-to-${localZoneName}" (
          mkIf (hostCfg.firewallRuleForNode ? ${name}) {
            from = [ "wg-${hostCfg.linkName}-node-${name}" ];
            to = [ localZoneName ];
            ignoreEmptyRule = true;

            inherit (hostCfg.firewallRuleForNode.${name})
              allowedTCPPorts
              allowedUDPPorts
              ;

          }
        )
      ))
    )
  );
  age.secrets = flip concatMapAttrs memberWG (
    networkName: networkCfg:
    let
      serverNode = filterAttrs (_: cfg: cfg.server) networkCfg.hosts;
      connectedPeers = if hostCfg.server then peers else serverNode;
      hostCfg = networkCfg.hosts.${config.node.name};
      peers = filterAttrs (name: _: name != config.node.name) networkCfg.hosts;
      sortedPeers =
        peerA: peerB:
        if peerA < peerB then
          {
            peer1 = peerA;
            peer2 = peerB;
          }
        else
          {
            peer1 = peerB;
            peer2 = peerA;
          };

      peerPrivateKeyFile = peerName: "/secrets/wireguard/${networkName}/keys/${peerName}.age";
      peerPrivateKeyPath = peerName: inputs.self.outPath + peerPrivateKeyFile peerName;
      peerPrivateKeySecret = peerName: "wireguard-${networkName}-priv-${peerName}";
      peerPresharedKeyFile =
        peerA: peerB:
        let
          inherit (sortedPeers peerA peerB) peer1 peer2;
        in
        "/secrets/wireguard/${networkName}/psks/${peer1}+${peer2}.age";
      peerPresharedKeyPath = peerA: peerB: inputs.self.outPath + peerPresharedKeyFile peerA peerB;
      peerPresharedKeySecret =
        peerA: peerB:
        let
          inherit (sortedPeers peerA peerB) peer1 peer2;
        in
        "wireguard-${networkName}-psks-${peer1}+${peer2}";
    in
    flip mapAttrs' connectedPeers (
      name: _:
      nameValuePair (peerPresharedKeySecret config.node.name name) {
        rekeyFile = peerPresharedKeyPath config.node.name name;
        owner = "systemd-network";
        generator.script = { pkgs, ... }: "${pkgs.wireguard-tools}/bin/wg genpsk";
      }
    )
    // {
      ${peerPrivateKeySecret config.node.name} = {
        rekeyFile = peerPrivateKeyPath config.node.name;
        owner = "systemd-network";
        generator.script =
          {
            pkgs,
            file,
            ...
          }:
          ''
            priv=$(${pkgs.wireguard-tools}/bin/wg genkey)
            ${pkgs.wireguard-tools}/bin/wg pubkey <<< "$priv" > ${
              lib.escapeShellArg (lib.removeSuffix ".age" file + ".pub")
            }
            echo "$priv"
          '';
      };
    }
  );
  systemd.network.netdevs = flip mapAttrs' memberWG (
    networkName: networkCfg:
    let
      serverNode = filterAttrs (_: cfg: cfg.server) networkCfg.hosts;
      hostCfg = networkCfg.hosts.${config.node.name};
      peers = filterAttrs (name: _: name != config.node.name) networkCfg.hosts;
      sortedPeers =
        peerA: peerB:
        if peerA < peerB then
          {
            peer1 = peerA;
            peer2 = peerB;
          }
        else
          {
            peer1 = peerB;
            peer2 = peerA;
          };

      peerPublicKeyFile = peerName: "/secrets/wireguard/${networkName}/keys/${peerName}.pub";
      peerPublicKeyPath = peerName: inputs.self.outPath + peerPublicKeyFile peerName;

      peerPrivateKeySecret = peerName: "wireguard-${networkName}-priv-${peerName}";
      peerPresharedKeySecret =
        peerA: peerB:
        let
          inherit (sortedPeers peerA peerB) peer1 peer2;
        in
        "wireguard-${networkName}-psks-${peer1}+${peer2}";
    in
    nameValuePair "${hostCfg.unitConfName}" {
      netdevConfig = {
        Kind = "wireguard";
        Name = hostCfg.linkName;
        Description = "Wireguard network ${networkName}";
      };
      wireguardConfig =
        {
          PrivateKeyFile = config.age.secrets.${peerPrivateKeySecret config.node.name}.path;
        }
        // optionalAttrs hostCfg.server {
          ListenPort = networkCfg.port;
        };
      wireguardPeers =
        if hostCfg.server then
          # All client nodes that have their via set to us.
          mapAttrsToList (clientName: clientCfg: {
            PublicKey = builtins.readFile (peerPublicKeyPath clientName);
            PresharedKeyFile = config.age.secrets.${peerPresharedKeySecret config.node.name clientName}.path;
            AllowedIPs =
              (optional (clientCfg.ipv4 != null) (net.cidr.make 32 clientCfg.ipv4))
              ++ (optional (clientCfg.ipv6 != null) (net.cidr.make 128 clientCfg.ipv6));
          }) peers
        else
          # We are a client node, so only include our via server.
          mapAttrsToList (
            serverName: _:
            {
              PublicKey = builtins.readFile (peerPublicKeyPath serverName);
              PresharedKeyFile = config.age.secrets.${peerPresharedKeySecret config.node.name serverName}.path;
              Endpoint = "${networkCfg.host}:${toString networkCfg.port}";
              # Access to the whole network is routed through our entry node.
              AllowedIPs =
                (optional (networkCfg.cidrv4 != null) networkCfg.cidrv4)
                ++ (optional (networkCfg.cidrv6 != null) networkCfg.cidrv6);
            }
            // optionalAttrs hostCfg.keepalive {
              PersistentKeepalive = 25;
            }
          ) serverNode;
    }
  );
  systemd.network.networks = flip mapAttrs' memberWG (
    _: networkCfg:
    let
      hostCfg = networkCfg.hosts.${config.node.name};
    in
    nameValuePair hostCfg.unitConfName {
      matchConfig.Name = hostCfg.linkName;
      address =
        (optional (networkCfg.cidrv4 != null) (net.cidr.hostCidr hostCfg.id networkCfg.cidrv4))
        ++ (optional (networkCfg.cidrv6 != null) (net.cidr.hostCidr hostCfg.id networkCfg.cidrv6));
    }
  );
}
