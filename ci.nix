# Buildable / cacheable package outputs for NUR CI.
#
# Filters the attrset returned by ./default.nix down to derivations that:
#   - aren't marked broken or non-free,
#   - aren't preferLocalBuild (i.e. worth caching).
#
# Mirrors the upstream nur-packages-template's ci.nix.
{
  pkgs ? import <nixpkgs> { },
  buildGradlePackage ? null,
}:

with builtins;
let
  isReserved =
    n:
    n == "lib"
    || n == "overlays"
    || n == "nixosModules"
    || n == "homeModules"
    || n == "darwinModules"
    || n == "flakeModules";
  isDerivation = p: isAttrs p && p ? type && p.type == "derivation";
  isBuildable =
    p:
    let
      licenseFromMeta = p.meta.license or [ ];
      licenseList = if isList licenseFromMeta then licenseFromMeta else [ licenseFromMeta ];
    in
    !(p.meta.broken or false) && all (license: license.free or true) licenseList;
  isCacheable = p: !(p.preferLocalBuild or false);
  shouldRecurseForDerivations = p: isAttrs p && p.recurseForDerivations or false;

  nameValuePair = n: v: {
    name = n;
    value = v;
  };

  flattenPkgs =
    s:
    let
      f =
        p:
        if shouldRecurseForDerivations p then
          flattenPkgs p
        else if isDerivation p then
          [ p ]
        else
          [ ];
    in
    concatMap f (attrValues s);

  outputsOf = p: map (o: p.${o}) p.outputs;

  nurAttrs = import ./default.nix (
    { inherit pkgs; }
    // (if buildGradlePackage != null then { inherit buildGradlePackage; } else { })
  );

  nurPkgs = flattenPkgs (
    listToAttrs (
      map (n: nameValuePair n nurAttrs.${n}) (filter (n: !isReserved n) (attrNames nurAttrs))
    )
  );

in
rec {
  buildPkgs = filter isBuildable nurPkgs;
  cachePkgs = filter isCacheable buildPkgs;

  buildOutputs = concatMap outputsOf buildPkgs;
  cacheOutputs = concatMap outputsOf cachePkgs;
}
