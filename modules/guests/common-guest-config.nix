_guestName: guestCfg: {lib, ...}: let
  inherit (lib) mkForce;
in {
  node.name = guestCfg.nodeName;
  node.type = guestCfg.backend;

  nix = {
    settings.auto-optimise-store = mkForce false;
    optimise.automatic = mkForce false;
    gc.automatic = mkForce false;
  };

  systemd.network.networks."10-${guestCfg.networking.mainLinkName}" = {
    matchConfig.Name = guestCfg.networking.mainLinkName;
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
  };
}
