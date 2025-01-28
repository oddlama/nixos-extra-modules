inputs: final: prev:
prev.lib.composeManyExtensions (
  # Order is important to allow using prev instead of final in more places to
  # speed up evaluation.
  (map (x: import x inputs) [
    # No dependencies
    ./lib/types.nix
    # No dependencies
    ./lib/misc.nix
    # No dependencies
    ./lib/disko.nix
    # Requires misc
    ./lib/net.nix
    # Requires misc, types
    ./lib/wireguard.nix
  ])
  ++ [
    (import ./pkgs)
  ]
)
final
prev
