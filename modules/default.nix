{ inputs, ... }:
{
  imports = [
    inputs.microvm.nixosModules.host

    ./boot.nix
    ./globals.nix
    ./guests/default.nix
    ./interface-naming.nix
    ./nginx.nix
    ./node.nix
    ./restic.nix
    #./topology-wireguard.nix
    ./wireguard.nix
  ];

  nixpkgs.overlays = [
    inputs.microvm.overlay
  ];
}
