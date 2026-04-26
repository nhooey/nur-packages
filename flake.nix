{
  description = "nhooey's NUR packages (aggregator)";

  # =====================================================================
  # Adding another of your Nix flake repos to this aggregator
  # =====================================================================
  # Add ONE input block below — that's it. Every input that isn't listed in
  # `infrastructureInputs` (in the `outputs` let-binding) is treated as a
  # downstream NUR-style flake. Its `packages.<system>` and
  # `legacyPackages.<system>` outputs are merged into this flake's, so:
  #
  #     nix run github:nhooey/nur-packages#<name>
  #
  # works for any package any of your repos exposes.
  #
  # Example (commented out — uncomment / add when ready):
  #
  #     skills-nix = {
  #       url = "github:nhooey/skills-nix";
  #       inputs.nixpkgs.follows = "nixpkgs";
  #     };
  #
  # Last-write-wins on name collisions; rename the package in its source
  # repo to disambiguate.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    gradle2nix = {
      url = "github:nhooey/gradle2nix/v2_bugfix-remove-param-console-plain";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    skills-git = {
      url = "github:nhooey/skills-git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    skills-nix = {
      url = "github:nhooey/skills-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, gradle2nix, ... }@inputs:
    let
      lib = nixpkgs.lib;

      # Inputs that power this flake itself, not downstream package repos.
      # Everything else in `inputs` is treated as an aggregated repo.
      infrastructureInputs = [ "self" "nixpkgs" "gradle2nix" ];

      aggregatedInputs = builtins.removeAttrs inputs infrastructureInputs;

      # Restrict to systems gradle2nix actually has a builder for; otherwise
      # evaluating `legacyPackages.${system}` on an unsupported host errors.
      forAllSystems = lib.genAttrs (builtins.attrNames gradle2nix.builders);

      pkgsFor = system: import nixpkgs { inherit system; };

      localAttrsFor =
        system:
        import ./default.nix {
          pkgs = pkgsFor system;
          buildGradlePackage = gradle2nix.builders.${system}.buildGradlePackage;
        };

      # Pulls one flake-output field (e.g. "packages") from every aggregated
      # input for `system`, with `{ }` if that input doesn't expose the field
      # or doesn't support that system. Plain `//` merge — last input wins.
      aggregatedFor =
        field: system:
        lib.foldl' (acc: input: acc // (input.${field}.${system} or { })) { } (
          builtins.attrValues aggregatedInputs
        );
    in
    {
      legacyPackages = forAllSystems (
        system: localAttrsFor system // aggregatedFor "legacyPackages" system
      );

      packages = forAllSystems (
        system:
        lib.filterAttrs (_: lib.isDerivation) (localAttrsFor system)
        // aggregatedFor "packages" system
      );
    };
}
