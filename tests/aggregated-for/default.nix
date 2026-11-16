# The `aggregated-for` check in flake.nix: lib/aggregated-for.nix over
# hand-made inputs, one per rule it applies.
{ pkgs }:
let
  inherit (pkgs) lib;
  aggregatedFor = import ../../lib/aggregated-for.nix {
    inherit lib;
    metaKeys = [ "default" ];
  };

  inputs = {
    # Only `default`: promoted to the input's name.
    single.packages.sys.default = "single-default";
    # Named packages: `default` is dropped, not promoted.
    named.packages.sys = {
      default = "named-default";
      tool = "named-tool";
      shared = "from-named";
    };
    # Sorted after `named`, so its `shared` wins.
    zlast.packages.sys.shared = "from-zlast";
    # No such field, or not this system: contributes nothing.
    nofield.homeModules.default = "module";
    othersystem.packages.other.default = "other-default";
    # An empty set for this system: contributes nothing, promotes nothing.
    empty.packages.sys = { };
  };
  result = aggregatedFor inputs "packages" "sys";
  expected = {
    single = "single-default";
    tool = "named-tool";
    shared = "from-zlast";
  };
in
assert lib.assertMsg (result == expected) "aggregatedFor: got ${builtins.toJSON result}";
assert aggregatedFor inputs "packages" "missing-system" == { };
assert aggregatedFor { } "packages" "sys" == { };
pkgs.writeText "aggregated-for" (builtins.toJSON result)
