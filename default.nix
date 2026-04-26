# NUR-style entrypoint.
#
# Returns a set of derivations callers can build with `nix-build -A <name>` or
# consume via `pkgs.nur.repos.nhooey.<name>` once registered with NUR.
#
# `buildGradlePackage` comes from the gradle2nix flake — it is not in nixpkgs,
# so flake-less callers must thread it in explicitly. The root flake.nix does
# this automatically.
{
  pkgs ? import <nixpkgs> { },
  buildGradlePackage ? throw ''
    nur-packages: the `xtdb` package needs `buildGradlePackage` from gradle2nix,
    which is not in nixpkgs. Use the flake interface
    (`nix build github:nhooey/nur-packages#xtdb`) or pass it explicitly:
      (import ./. { inherit pkgs buildGradlePackage; }).xtdb
  '',
}:

{
  xtdb = pkgs.callPackage ./pkgs/servers/sql/xtdb {
    inherit pkgs buildGradlePackage;
  };
}
