{inputs, ...}: {
  imports = [
    inputs.microvm.nixosModules.host

    ./boot.nix
    ./guests/default.nix
    ./interface-naming.nix
    ./nginx.nix
    ./node.nix
    ./restic.nix
    ./wireguard.nix
  ];

  nixpkgs.overlays = [
    inputs.microvm.overlay
  ];
}
