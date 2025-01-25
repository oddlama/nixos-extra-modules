inputs: final: prev: let
  inherit
    (inputs.nixpkgs.lib)
    assertMsg
    attrNames
    attrValues
    concatLists
    concatMap
    filter
    flip
    genAttrs
    partition
    warn
    ;

  inherit
    (final.lib)
    net
    types
    ;
in {
  lib =
    prev.lib
    // rec {
      wireguard.evaluateNetwork = userInputs: wgName: let
        inherit (userInputs.self) nodes;
        # Returns the given node's wireguard configuration of this network
        wgCfgOf = node: nodes.${node}.config.wireguard.${wgName};

        sortedPeers = peerA: peerB:
          if peerA < peerB
          then {
            peer1 = peerA;
            peer2 = peerB;
          }
          else {
            peer1 = peerB;
            peer2 = peerA;
          };

        peerPublicKeyFile = peerName: "/secrets/wireguard/${wgName}/keys/${peerName}.pub";
        peerPublicKeyPath = peerName: userInputs.self.outPath + peerPublicKeyFile peerName;

        peerPrivateKeyFile = peerName: "/secrets/wireguard/${wgName}/keys/${peerName}.age";
        peerPrivateKeyPath = peerName: userInputs.self.outPath + peerPrivateKeyFile peerName;
        peerPrivateKeySecret = peerName: "wireguard-${wgName}-priv-${peerName}";

        peerPresharedKeyFile = peerA: peerB: let
          inherit (sortedPeers peerA peerB) peer1 peer2;
        in "/secrets/wireguard/${wgName}/psks/${peer1}+${peer2}.age";
        peerPresharedKeyPath = peerA: peerB: userInputs.self.outPath + peerPresharedKeyFile peerA peerB;
        peerPresharedKeySecret = peerA: peerB: let
          inherit (sortedPeers peerA peerB) peer1 peer2;
        in "wireguard-${wgName}-psks-${peer1}+${peer2}";

        # All nodes that are part of this network
        participatingNodes = filter (n: builtins.hasAttr wgName nodes.${n}.config.wireguard) (
          attrNames nodes
        );

        # Partition nodes by whether they are servers
        _participatingNodes_isServerPartition =
          partition (
            n: (wgCfgOf n).server.host != null
          )
          participatingNodes;

        participatingServerNodes = _participatingNodes_isServerPartition.right;
        participatingClientNodes = _participatingNodes_isServerPartition.wrong;

        # Maps all nodes that are part of this network to their addresses
        nodePeers = genAttrs participatingNodes (n: (wgCfgOf n).addresses);

        # A list of all occurring addresses.
        usedAddresses = concatMap (n: (wgCfgOf n).addresses) participatingNodes;

        # A list of all occurring addresses, but only includes addresses that
        # are not assigned automatically.
        explicitlyUsedAddresses = flip concatMap participatingNodes (
          n:
            filter (x: !types.isLazyValue x) (
              concatLists
              (nodes.${n}.options.wireguard.type.nestedTypes.elemType.getSubOptions (wgCfgOf n))
              .addresses
              .definitions
            )
        );

        # The cidrv4 and cidrv6 of the network spanned by all participating peer addresses.
        # This also takes into account any reserved address ranges that should be part of the network.
        networkAddresses = net.cidr.merge (
          usedAddresses ++ concatMap (n: (wgCfgOf n).server.reservedAddresses) participatingServerNodes
        );

        # The network spanning cidr addresses. The respective cidrv4 and cirdv6 are only
        # included if they exist.
        networkCidrs = filter (x: x != null) (attrValues networkAddresses);

        # The cidrv4 and cidrv6 of the network spanned by all reserved addresses only.
        # Used to determine automatically assigned addresses first.
        spannedReservedNetwork = net.cidr.merge (
          concatMap (n: (wgCfgOf n).server.reservedAddresses) participatingServerNodes
        );

        # Assigns an ipv4 address from spannedReservedNetwork.cidrv4
        # to each participant that has not explicitly specified an ipv4 address.
        assignedIpv4Addresses = assert assertMsg (spannedReservedNetwork.cidrv4 != null)
        "Wireguard network '${wgName}': At least one participating node must reserve a cidrv4 address via `reservedAddresses` so that ipv4 addresses can be assigned automatically from that network.";
          net.cidr.assignIps spannedReservedNetwork.cidrv4
          # Don't assign any addresses that are explicitly configured on other hosts
          (filter (x: net.cidr.contains x spannedReservedNetwork.cidrv4) (
            filter net.ip.isv4 explicitlyUsedAddresses
          ))
          participatingNodes;

        # Assigns an ipv6 address from spannedReservedNetwork.cidrv6
        # to each participant that has not explicitly specified an ipv6 address.
        assignedIpv6Addresses = assert assertMsg (spannedReservedNetwork.cidrv6 != null)
        "Wireguard network '${wgName}': At least one participating node must reserve a cidrv6 address via `reservedAddresses` so that ipv6 addresses can be assigned automatically from that network.";
          net.cidr.assignIps spannedReservedNetwork.cidrv6
          # Don't assign any addresses that are explicitly configured on other hosts
          (filter (x: net.cidr.contains x spannedReservedNetwork.cidrv6) (
            filter net.ip.isv6 explicitlyUsedAddresses
          ))
          participatingNodes;

        # Appends / replaces the correct cidr length to the argument,
        # so that the resulting address is in the cidr.
        toNetworkAddr = addr: let
          relevantNetworkAddr =
            if net.ip.isv6 addr
            then networkAddresses.cidrv6
            else networkAddresses.cidrv4;
        in "${net.cidr.ip addr}/${toString (net.cidr.length relevantNetworkAddr)}";
      in {
        inherit
          assignedIpv4Addresses
          assignedIpv6Addresses
          explicitlyUsedAddresses
          networkAddresses
          networkCidrs
          nodePeers
          participatingClientNodes
          participatingNodes
          participatingServerNodes
          peerPresharedKeyFile
          peerPresharedKeyPath
          peerPresharedKeySecret
          peerPrivateKeyFile
          peerPrivateKeyPath
          peerPrivateKeySecret
          peerPublicKeyFile
          peerPublicKeyPath
          sortedPeers
          spannedReservedNetwork
          toNetworkAddr
          usedAddresses
          wgCfgOf
          ;
      };

      wireguard.createEvalCache = userInputs: wgNames: genAttrs wgNames (wireguard.evaluateNetwork userInputs);

      wireguard.getNetwork = userInputs: wgName:
        userInputs.self.wireguardEvalCache.${wgName}
        or (warn ''
          The calculated information for the wireguard network "${wgName}" is not cached!
          This will siginificantly increase evaluation times. Please consider pre-evaluating
          this information by exposing it in your flake:

            wireguardEvalCache = lib.wireguard.createEvalCache inputs [
              "${wgName}"
              # all other networks
            ];

        '' (wireguard.evaluateNetwork userInputs wgName));
    };
}
