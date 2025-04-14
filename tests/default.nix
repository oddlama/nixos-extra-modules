{
  nixt,
  pkgs,
  ...
}:
[
  (import ./shift.nix { inherit pkgs nixt; })
]
