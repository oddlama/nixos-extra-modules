_final: prev: {
  home-assistant-custom-lovelace-modules =
    prev.home-assistant-custom-lovelace-modules
    // {
      bar-card = prev.callPackage ./home-assistant/bar-card.nix {};
    };
}
