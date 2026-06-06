{
  description = "nur-packages dev-shell skill set — an isolated sub-flake invoked at RUNTIME by the root devShell, never a root input. The skill sources (git-skills's git/GitHub pack, skillspkgs' authoring combination, and the nix-bump skill from nix-skills) live only in THIS flake's lock, so the root nur-packages stays free of the skill mesh and transitive consumers never drag it in.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";

    # `agent-skill-flake` is the builder library, not a skill — it provides
    # `mkDevshellSkillsFlake` (which runs `mkCombination` under the hood).
    agent-skill-flake = {
      url = "github:nhooey/agent-skill-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Every input below this divider is a skill source feeding the dev shell.
    #
    # They follow this flake's `nixpkgs` but NOT the builder lib: the root pins
    # a newer owner-namespacing `agent-skill-flake`/`agent-skill-flake`, and forcing
    # the `authoring` combination's transitive sources onto it surfaces an
    # ownerless aggregate-key the strict namespace check rejects. Letting each
    # source keep its own (compatible) builder-lib rev matches how the inputs
    # behaved when they were inlined in the root; `mkDevshellSkillsFlake` still
    # runs from THIS flake's `agent-skill-flake.lib`, so the combiner is the
    # pinned sub-flake rev.

    # git-skills's git/GitHub skill pack.
    git-skills = {
      url = "github:nhooey/git-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nix-skills: the nix-bump skill is cherry-picked below; the source is
    # pulled whole and the subset is selected in the combination's `sources`
    # entry.
    nix-skills = {
      url = "github:nhooey/nix-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # skillspkgs' curated `authoring` combination, surfaced through its own
    # subdir flake (`mkCombination` keeps a combination re-composable).
    skillspkgs-combinations = {
      url = "github:nhooey/skillspkgs?dir=sources/combinations";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      agent-skill-flake,
      git-skills,
      nix-skills,
      skillspkgs-combinations,
      ...
    }@inputs:
    agent-skill-flake.lib.mkDevshellSkillsFlake {
      inherit nixpkgs;
      systems = import inputs.systems;
      name = "nur-packages-devshell";
      sources = [
        { source = git-skills; }
        { source = skillspkgs-combinations.combinations.authoring; }
        {
          source = nix-skills;
          skills = [ "nix-flake-recursive-bump-input-versions" ];
        }
      ];
    };
}
