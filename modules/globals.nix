{ lib, options, ... }:
{
  options._globalsDefs = lib.mkOption {
    type = lib.types.unspecified;
    default = options.globals.definitions;
    readOnly = true;
    internal = true;
  };
}
