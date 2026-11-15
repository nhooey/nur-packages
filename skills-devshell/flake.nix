{
  description = "nur-packages dev-shell skill set — an isolated sub-flake invoked at RUNTIME by the root devShell, never a root input. The skill sources live only in THIS flake's lock, so the root nur-packages stays free of the skill mesh and transitive consumers never drag it in.";

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
    # They follow this flake's `nixpkgs` but NOT the builder lib: forcing the
    # `authoring` combination's transitive sources onto this flake's
    # `agent-skill-flake` surfaces an ownerless aggregate-key the strict
    # namespace check rejects. `mkDevshellSkillsFlake` still runs from THIS
    # flake's `agent-skill-flake.lib`, so the combiner is the pinned rev.

    # Running a prompt as a headless session in other checkouts, keeping the
    # scratchpad tidy, and the cross-repository plan's graph.
    coding-agent-skills = {
      url = "github:nhooey/coding-agent-skills/overnight-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The git/GitHub skill pack.
    git-skills = {
      url = "github:nhooey/git-skills/overnight-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix flake conventions and the recursive input bump.
    nix-skills = {
      url = "github:nhooey/nix-skills/overnight-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Safe shell commands: named deletes, PIDs, no machine-wide changes.
    shell-skills = {
      url = "github:nhooey/shell-skills/overnight-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # skillspkgs' curated `authoring` combination, surfaced through its own
    # subdir flake (`mkCombination` keeps a combination re-composable). Its
    # git-skills and nix-skills follow the ones above, so one rev of each
    # lands in the shell.
    skillspkgs-combinations = {
      url = "github:nhooey/skillspkgs?dir=sources/combinations";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-skills.follows = "git-skills";
      inputs.nix-skills.follows = "nix-skills";
    };
  };

  outputs =
    {
      nixpkgs,
      agent-skill-flake,
      ...
    }@inputs:
    agent-skill-flake.lib.mkDevshellSkillsFlake {
      inherit nixpkgs;
      systems = import inputs.systems;
      name = "nur-packages-devshell";
      sources = [
        { source = inputs.git-skills; }
        { source = inputs.shell-skills; }
        { source = inputs.skillspkgs-combinations.combinations.authoring; }
        {
          source = inputs.nix-skills;
          skills = [
            "nix-flakes"
            "nix-flake-recursive-bump-input-versions"
          ];
        }
        {
          source = inputs.coding-agent-skills;
          skills = [
            "coding-agent-headless-in-checkout"
            "coding-agent-plans-as-graph"
            "coding-agent-scratchpad-scripts"
          ];
        }
      ];
    };
}
