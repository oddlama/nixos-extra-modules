{
  nixt,
  pkgs,
  ...
}:
let
  inherit (nixt.lib) block describe it;
  inherit (pkgs) lib;
  expected = {
    cidrv6 = {
      empty = {
        base = {
          ipv6 = {
            a = 0;
            b = 0;
            c = 0;
            d = 0;
          };
        };
        length = 0;
      };
      base4 = {
        base = {
          ipv6 = {
            a = 65536;
            b = 0;
            c = 0;
            d = 0;
          };
        };
        length = 4;
      };
    };
  };
in
block ./net.nix [
  (describe "cidrv6" [
    (it "child 1" (lib.net.cidr.child "1::/4" "0::/0"))
    (it "child 2" (lib.net.cidr.child "1::/4" "::/0"))
    (it "child 3" (!lib.net.cidr.child "::/0" "::/4"))
    (it "child 4" (lib.net.cidr.child "1100::/8" "1000::/4"))
    (it "child 5" (!lib.net.cidr.child "1100::/16" "1000::/8"))
    (it "child 6" (lib.net.cidr.child "0:1::/24" "0:1::/8"))

    (it "typechecks 1" (lib.typechecks.cidr "" "" "::/0" == expected.cidrv6.empty))
    (it "typechecks 2" (lib.typechecks.cidr "" "" "0::/0" == expected.cidrv6.empty))
    (it "typechecks 3" (lib.typechecks.cidr "" "" "1::/4" == expected.cidrv6.empty // { length = 4; }))

    (it "impl child" (lib.implementations.cidr.child expected.cidrv6.base4 expected.cidrv6.empty))

    (it "cidr length 0" (lib.implementations.cidr.length expected.cidrv6.empty == 0))
    (it "cidr length 4" (lib.implementations.cidr.length expected.cidrv6.base4 == 4))

    (it "contains 4" (
      lib.implementations.cidr.contains expected.cidrv6.base4.base expected.cidrv6.empty
    ))

    (it "host 4" (lib.implementations.cidr.host 0 expected.cidrv6.base4 == expected.cidrv6.base4.base))
    (it "host 0" (lib.implementations.cidr.host 0 expected.cidrv6.empty == expected.cidrv6.empty.base))

    (it "make len 0" (
      lib.implementations.cidr.make 0 expected.cidrv6.base4.base == expected.cidrv6.empty
    ))
    (it "make base 4 len 0 length" (
      (lib.implementations.cidr.make 0 expected.cidrv6.base4.base).length == 0
    ))
    (it "make base 4 len 0 base" (
      (lib.implementations.cidr.make 0 expected.cidrv6.base4.base).base == expected.cidrv6.empty.base
    ))
  ])
  (describe "cidrv4" [
    (it "child 1" (lib.net.cidr.child "10.10.10.0/24" "10.0.0.0/8"))
    (it "child 2" (!lib.net.cidr.child "127.0.0.0/24" "10.0.0.0/8"))
  ])
  (describe "arithmetic" [
    (it "coshadow 1" (
      (lib.arithmetic.coshadow 0 expected.cidrv6.base4.base) == expected.cidrv6.empty.base
    ))
    (it "coerce 1" (
      (lib.arithmetic.coerce expected.cidrv6.base4.base (-1)) == {
        ipv6 = {
          a = 4294967295;
          b = 4294967295;
          c = 4294967295;
          d = 4294967295;
        };
      }
    ))
  ])
  (describe "bit" [
    (it "mask 32 " ((lib.bit.mask 32 (-1)) == 4294967295))
  ])
]
