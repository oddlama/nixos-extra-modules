inputs: final: prev:
prev.lib.composeManyExtensions (
  # Order is important to allow using prev instead of final in more places to
  # speed up evaluation.
  map (x: import x inputs) [
    # No dependencies
    ./types.nix
    # No dependencies
    ./misc.nix
    # No dependencies
    ./disko.nix
    # Requires misc
    ./net.nix
    # Requires misc, types
    ./wireguard.nix
  ]
)
final
prev
