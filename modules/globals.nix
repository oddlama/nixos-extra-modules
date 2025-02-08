{ lib, options, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    globals = mkOption {
      default = { };
      type = types.submodule { };
    };
    _globalsDefs = mkOption {
      type = types.unspecified;
      default = options.globals.definitions;
      readOnly = true;
      internal = true;
    };
  };
}
