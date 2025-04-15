let
  # lut = [
  #   1 # 0
  #   2 # 1
  #   4 # 2
  #   8 # 3
  #   16 # 4
  #   32 # 5
  #   64 # 6
  #   128 # 7
  #   256 # 8
  #   512 # 9
  #   1024 # 10
  #   2048 # 11
  #   4096 # 12
  #   8192 # 13
  #   16384 # 14
  #   32768 # 15
  #   65536 # 16
  #   131072 # 17
  #   262144 # 18
  #   524288 # 19
  #   1048576 # 20
  #   2097152 # 21
  #   4194304 # 22
  #   8388608 # 23
  #   16777216 # 24
  #   33554432 # 25
  #   67108864 # 26
  #   134217728 # 27
  #   268435456 # 28
  #   536870912 # 29
  #   1073741824 # 30
  #   2147483648 # 31
  #   4294967296 # 32
  #   8589934592 # 33
  #   17179869184 # 34
  #   34359738368 # 35
  #   68719476736 # 36
  #   137438953472 # 37
  #   274877906944 # 38
  #   549755813888 # 39
  #   1099511627776 # 40
  #   2199023255552 # 41
  #   4398046511104 # 42
  #   8796093022208 # 43
  #   17592186044416 # 44
  #   35184372088832 # 45
  #   70368744177664 # 46
  #   140737488355328 # 47
  #   281474976710656 # 48
  #   562949953421312 # 49
  #   1125899906842624 # 50
  #   2251799813685248 # 51
  #   4503599627370496 # 52
  #   9007199254740992 # 53
  #   18014398509481984 # 54
  #   36028797018963968 # 55
  #   72057594037927936 # 56
  #   144115188075855872 # 57
  #   288230376151711744 # 58
  #   576460752303423488 # 59
  #   1152921504606846976 # 60
  #   2305843009213693952 # 61
  #   4611686018427387904 # 62
  # ];
  lut = builtins.foldl' (l: n: l ++ [ (2 * builtins.elemAt l n) ]) [ 1 ] (builtins.genList (x: x) 62);
  intmin = (-9223372036854775807) - 1;
  intmax = 9223372036854775807;
  left =
    a: b:
    if a >= 64 then
      # It's allowed to shift out all bits
      0
    else if a == 0 then
      b
    else if a < 0 then
      throw "Inverse Left Shift not supported"
    else
      let
        inv = 63 - a;
        mask = if inv == 63 then intmax else (builtins.elemAt lut inv) - 1;
        masked = builtins.bitAnd b mask;
        checker = if inv == 63 then intmin else builtins.elemAt lut inv;
        negate = (builtins.bitAnd b checker) != 0;
        mult = if a == 63 then intmin else builtins.elemAt lut a;
        result = masked * mult;
      in
      if !negate then result else intmin + result;
  logicalRight =
    a: b:
    if a >= 64 then
      0
    else if a == 0 then
      b
    else if a < 0 then
      throw "Inverse right Shift not supported"
    else
      let
        masked = builtins.bitAnd b intmax;
        negate = b < 0;
        # Split division to prevent having to divide by a negative number for
        # shifts of 63 bit
        result = masked / 2 / (builtins.elemAt lut (a - 1));
        inv = 63 - a;
        highest_bit = builtins.elemAt lut inv;
      in
      if !negate then result else result + highest_bit;
  arithmeticRight =
    a: b:
    if a >= 64 then
      if b < 0 then -1 else 0
    else if a == 0 then
      b
    else if a < 0 then
      throw "Inverse right Shift not supported"
    else
      let
        negate = b < 0;
        mask = if a == 63 then intmax else (builtins.elemAt lut a) - 1;
        round_down = negate && (builtins.bitAnd mask b != 0);
        result = b / 2 / (builtins.elemAt lut (a - 1));
      in
      if round_down then result - 1 else result;
in
{
  inherit left logicalRight arithmeticRight;
}
