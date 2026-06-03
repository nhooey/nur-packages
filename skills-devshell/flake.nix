{
  description = "nur-packages dev-shell skills: the skill set installed into the nur-packages dev shell for working on this repo (git/GitHub hygiene, skillspkgs' authoring combination, and the nix-flake-recursive-bump-input-versions skill) — kept in its own sub-flake so its skill-source inputs stay out of the parent's inputs.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    systems.url = "github:nix-systems/default";

    # `flake-skills` is the builder library, not a skill — it provides
    # `mkCombination`. Followed by every skill source below so the whole tree
    # shares one evaluation.
    flake-skills = {
      url = "github:nhooey/flake-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Every input below this divider is a skill source.
    skills-git = {
      url = "github:nhooey/skills-git";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-skills.follows = "flake-skills";
      };
    };

    # The nix-flake-recursive-bump-input-versions skill is cherry-picked from
    # skills-nix below.
    skills-nix = {
      url = "github:nhooey/skills-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-skills.follows = "flake-skills";
      };
    };

    # skillspkgs' curated `authoring` combination, spliced in as a single
    # source — mkCombination makes a combination re-composable, so this
    # references upstream curation instead of duplicating it.
    skillspkgs-combinations = {
      url = "github:nhooey/skillspkgs?dir=sources/combinations";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-skills.follows = "flake-skills";
      };
    };
  };

  outputs =
    {
      nixpkgs,
      flake-parts,
      systems,
      flake-skills,
      skills-git,
      skills-nix,
      skillspkgs-combinations,
      ...
    }@inputs:
    let
      forSystems = nixpkgs.lib.genAttrs (import systems);

      # No `skillsDir`: this flake outputs no skills of its own, it only
      # combines external sources into the dev-shell skill set the parent
      # installs in one reconcile — the git/GitHub pack, skillspkgs' `authoring`
      # combination, and the nix-bump skill cherry-picked from skills-nix.
      devshellSkills = flake-skills.lib.mkCombination {
        inherit nixpkgs;
        name = "nur-packages-devshell";
        envName = "agent-skills-nur-packages-devshell";
        packagePrefix = "agent-skill-";
        sources = [
          { source = skills-git; }
          { source = skillspkgs-combinations.combinations.authoring; }
          {
            source = skills-nix;
            skills = [ "nix-flake-recursive-bump-input-versions" ];
          }
        ];
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import systems;

      # The reconcile one-liner as ready-to-run TEXT, keyed by system — NOT a
      # `system -> string` function. The parent dev shell splices
      # `reconcileScript.${system}` straight into a startup hook.
      flake.reconcileScript = forSystems (system: devshellSkills.reconcileScript system);

      # `packages` / `apps` are surfaced per-system for `nix eval` / `nix run`
      # inspection of the combined set.
      perSystem =
        { system, ... }:
        {
          packages = devshellSkills.packages.${system};
          apps = devshellSkills.apps.${system};
        };
    };
}
