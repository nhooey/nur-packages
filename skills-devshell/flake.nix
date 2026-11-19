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

    # skillspkgs' per-family combinations, surfaced through their own subdir
    # flake. nur-packages is in the Nix tooling family, so the dev shell
    # takes `combinations.nix-tooling` as its one skill source; the rest of
    # the family shares every language and tool this repository uses, so it
    # adds nothing of its own.
    skillspkgs-combinations = {
      url = "github:nhooey/skillspkgs?dir=sources/combinations";
      inputs.nixpkgs.follows = "nixpkgs";
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
        { source = inputs.skillspkgs-combinations.combinations.nix-tooling; }
      ];
    };
}
