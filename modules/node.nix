{
  config,
  lib,
  ...
}: let
  inherit
    (lib)
    mkOption
    types
    ;
in {
  options.node = {
    name = mkOption {
      description = "A unique name for this node (host) in the repository. Defines the default hostname, but this can be overwritten.";
      type = types.str;
    };
  };

  config = {
    networking.hostName = config.node.name;
  };
}
