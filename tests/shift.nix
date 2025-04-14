{
  nixt,
  pkgs,
  ...
}:
let
  inherit (nixt.lib) block describe it;
  inherit (pkgs.lib.bit) left;
in
block ./shift.nix [
  (describe "" [
    (it "Single left shift" (left 1 1 == 2))
    (it "Single left shift" (left 1 2 == 2))
  ])
]
