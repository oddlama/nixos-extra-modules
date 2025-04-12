_inputs: final: prev:
let
  inherit (prev.lib)
    filter
    foldl'
    genAttrs
    mergeAttrs
    mkMerge
    stringToCharacters
    substring
    unique
    ;
  inherit (final.lib)
    bit
    ;

  # Counts how often each element occurrs in xs.
  # Elements must be strings.
  countOccurrences = foldl' (acc: x: acc // { ${x} = (acc.${x} or 0) + 1; }) { };

  # Returns all elements in xs that occur at least twice
  duplicates =
    xs:
    let
      occurrences = countOccurrences xs;
    in
    unique (filter (x: occurrences.${x} > 1) xs);

  # Concatenates all given attrsets as if calling a // b in order.
  concatAttrs = foldl' mergeAttrs { };

  # True if the path or string starts with /
  isAbsolutePath = x: substring 0 1 x == "/";

  # Merges all given attributes from the given attrsets using mkMerge.
  # Useful to merge several top-level configs in a module.
  mergeToplevelConfigs = keys: attrs: genAttrs keys (attr: mkMerge (map (x: x.${attr} or { }) attrs));

  hexLiteralValues = {
    "0" = 0;
    "1" = 1;
    "2" = 2;
    "3" = 3;
    "4" = 4;
    "5" = 5;
    "6" = 6;
    "7" = 7;
    "8" = 8;
    "9" = 9;
    "a" = 10;
    "b" = 11;
    "c" = 12;
    "d" = 13;
    "e" = 14;
    "f" = 15;
    "A" = 10;
    "B" = 11;
    "C" = 12;
    "D" = 13;
    "E" = 14;
    "F" = 15;
  };

  # Converts the given hex string to an integer. Only reliable for inputs in [0, 2^63),
  # after that the sign bit will overflow.
  hexToDec = v: foldl' (acc: x: (bit.left acc 4) + hexLiteralValues.${x}) 0 (stringToCharacters v);
in
{
  lib = prev.lib // {
    inherit
      hexToDec
      concatAttrs
      countOccurrences
      duplicates
      isAbsolutePath
      mergeToplevelConfigs
      ;
  };
}
