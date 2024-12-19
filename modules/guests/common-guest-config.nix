_guestName: guestCfg: {lib, ...}: let
  inherit
    (lib)
    mkForce
    nameValuePair
    listToAttrs
    flip
    ;
in {
  node.name = guestCfg.nodeName;
  node.type = guestCfg.backend;

  nix = {
    settings.auto-optimise-store = mkForce false;
    optimise.automatic = mkForce false;
    gc.automatic = mkForce false;
  };
  documentation.enable = mkForce false;

  systemd.network.networks = listToAttrs (
    flip map guestCfg.networking.links (
      name:
        nameValuePair "10-${name}" {
          matchConfig.Name = name;
          DHCP = "yes";
          # XXX: Do we really want this?
          dhcpV4Config.UseDNS = false;
          dhcpV6Config.UseDNS = false;
          ipv6AcceptRAConfig.UseDNS = false;
          networkConfig = {
            IPv6PrivacyExtensions = "yes";
            MulticastDNS = true;
            IPv6AcceptRA = true;
          };
          linkConfig.RequiredForOnline = "routable";
        }
    )
  );
}
