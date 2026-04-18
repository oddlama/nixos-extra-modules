{
  pkgs,
  globals,
  nixosConfigurations,
  inputs,
  decryptIdentity,
}:
let
  inherit (pkgs.lib)
    attrNames
    concatLines
    concatStringsSep
    elem
    escapeShellArg
    filterAttrs
    getExe
    head
    mapAttrsToList
    net
    optional
    removeSuffix
    ;

  nodeNames = attrNames nixosConfigurations;

  sortedPeerNames =
    a: b:
    if a < b then
      {
        peer1 = a;
        peer2 = b;
      }
    else
      {
        peer1 = b;
        peer2 = a;
      };

  peerCaseArms = concatLines (
    mapAttrsToList (
      netName: netCfg:
      let
        serverName = head (attrNames (filterAttrs (_: h: h.server) netCfg.hosts));
        serverPublicKey = removeSuffix "\n" (
          builtins.readFile (inputs.self.outPath + "/secrets/wireguard/${netName}/keys/${serverName}.pub")
        );
        externalPeers = filterAttrs (name: _: !(elem name nodeNames)) netCfg.hosts;
      in
      concatLines (
        mapAttrsToList (
          extName: extCfg:
          let
            addresses =
              (optional (extCfg.ipv4 != null) (net.cidr.hostCidr extCfg.id netCfg.cidrv4))
              ++ (optional (extCfg.ipv6 != null) (net.cidr.hostCidr extCfg.id netCfg.cidrv6));
            allowedIPs =
              (optional (netCfg.cidrv4 != null) netCfg.cidrv4)
              ++ (optional (netCfg.cidrv6 != null) netCfg.cidrv6);
            sorted = sortedPeerNames serverName extName;
          in
          ''
            "${netName}/${extName}")
              ADDRESSES=${escapeShellArg (concatStringsSep ", " addresses)}
              SERVER_PUBKEY=${escapeShellArg serverPublicKey}
              PSK_AGE_FILE="secrets/wireguard/${netName}/psks/${sorted.peer1}+${sorted.peer2}.age"
              PRIVKEY_AGE_FILE="secrets/wireguard/${netName}/keys/${extName}.age"
              ENDPOINT=${escapeShellArg "${netCfg.host}:${toString netCfg.port}"}
              ALLOWED_IPS=${escapeShellArg (concatStringsSep ", " allowedIPs)}
              ;;
          ''
        ) externalPeers
      )
    ) globals.wireguard
  );

  availablePeers = concatLines (
    mapAttrsToList (
      netName: netCfg:
      let
        externalPeers = filterAttrs (name: _: !(elem name nodeNames)) netCfg.hosts;
      in
      concatLines (mapAttrsToList (extName: _: "    ${netName} ${extName}") externalPeers)
    ) globals.wireguard
  );
in
{
  type = "app";
  program = getExe (pkgs.writeShellApplication {
    name = "wg-quick-config";
    runtimeInputs = with pkgs; [
      rage
      age-plugin-yubikey
    ];
    text = ''
      usage() {
        echo "Usage: wg-quick-config <network> <peer>"
        echo
        echo "Outputs a wg-quick configuration for an external peer."
        echo "Keys must be generated first via 'agenix generate'."
        echo
        echo "Available network/peer combinations:"
      ${availablePeers}
        exit 1
      }

      NETWORK="''${1:-}"
      PEER="''${2:-}"

      if [[ -z "$NETWORK" || -z "$PEER" ]]; then
        usage
      fi

      case "''${NETWORK}/''${PEER}" in
      ${peerCaseArms}
        *)
          echo "Unknown network/peer: ''${NETWORK}/''${PEER}" >&2
          echo "Run without arguments to see available combinations." >&2
          exit 1
          ;;
      esac

      IDENTITY=${escapeShellArg (toString decryptIdentity)}

      if [[ ! -f "$PRIVKEY_AGE_FILE" ]]; then
        echo "Private key not found: $PRIVKEY_AGE_FILE" >&2
        echo "Run 'agenix generate' first." >&2
        exit 1
      fi
      if [[ ! -f "$PSK_AGE_FILE" ]]; then
        echo "Pre-shared key not found: $PSK_AGE_FILE" >&2
        echo "Run 'agenix generate' first." >&2
        exit 1
      fi

      PRIVATE_KEY=$(rage -d -i "$IDENTITY" "$PRIVKEY_AGE_FILE")
      PSK=$(rage -d -i "$IDENTITY" "$PSK_AGE_FILE")

      cat <<EOF
      [Interface]
      PrivateKey = $PRIVATE_KEY
      Address = $ADDRESSES

      [Peer]
      PublicKey = $SERVER_PUBKEY
      PresharedKey = $PSK
      Endpoint = $ENDPOINT
      AllowedIPs = $ALLOWED_IPS
      PersistentKeepalive = 25
      EOF
    '';
  });
}
