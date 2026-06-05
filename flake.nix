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

    # Shared infrastructure inputs declared once at the root so every input
    # below can `follows` them to a single node, collapsing the duplicated
    # nix-systems / flake-parts / treefmt-nix subtrees that otherwise bloat
    # flake.lock. Listed in `infrastructureInputs` below so they are not
    # mistaken for aggregated package repos.
    systems.url = "github:nix-systems/default";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claffeinate = {
      url = "github:nhooey/claffeinate";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.devshell.follows = "devshell";
      inputs.agent-skill-flake.follows = "agent-skill-flake";
    };

    claude-in-nix-devshell = {
      url = "github:nhooey/claude-in-nix-devshell";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
      inputs.flake-parts.follows = "flake-parts";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.devshell.follows = "devshell";
      inputs.agent-skill-flake.follows = "agent-skill-flake";
    };

    cljfmt = {
      url = "github:nhooey/nix-cljfmt";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # numtide/devshell — hosts the dev-shell defined in `outputs.devShells`
    # below. Infrastructure-only (no packages to aggregate).
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Source of `darwinModules.default` below. Not aggregated as a package
    # repo — it exposes `darwinModules` / `lib`, no `packages`. The dev-shell
    # skill set no longer lives here: it has moved to the runtime
    # `skills-devshell/` sub-flake (invoked by the dev shell via
    # `agent-skill-flake.lib.devshellSkillsHook`), so the skill mesh is kept out
    # of this root's lock.
    agent-skill-flake = {
      url = "github:nhooey/agent-skill-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
      inputs.flake-parts.follows = "flake-parts";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.devshell.follows = "devshell";
    };

    gradle2nix = {
      url = "github:nhooey/gradle2nix/v2_bugfix-remove-param-console-plain";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The single conduit to every skills-* repo this flake aggregates as
    # packages. skillspkgs aggregates nhooey/{nix-gstack, skills-git,
    # skills-nix} and the third-party skill wrappers under `skillspkgs/pkgs/`,
    # so we rely on it to forward those packages (merged into this flake's
    # `packages.<system>`) instead of importing each repo as a direct input
    # here. This stays a root input because it feeds a NON-dev-shell output
    # (the aggregated package set), unlike the dev-shell-only skill sources now
    # isolated in `skills-devshell/`.
    skillspkgs = {
      url = "github:nhooey/skillspkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
      inputs.flake-parts.follows = "flake-parts";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.devshell.follows = "devshell";
      # NOTE: skillspkgs's `flake-skills` is intentionally NOT followed onto the
      # root `agent-skill-flake`. The root pins a newer builder-lib rev (for the
      # dev-shell `devshellSkillsHook` and the `darwinModules` hook) whose
      # stricter package-key namespace check rejects skillspkgs's vendored "all"
      # skill (an ownerless aggregate key), which would break the aggregated
      # `packages.<system>` output. Letting skillspkgs resolve its own compatible
      # builder-lib pin keeps that output building; the two builder-lib revs
      # coexist cleanly because nix does not auto-unify them.
    };
  };

  outputs =
    { self, nixpkgs, gradle2nix, agent-skill-flake, ... }@inputs:
    let
      lib = nixpkgs.lib;

      # Inputs that power this flake itself, not downstream package repos.
      # Everything else in `inputs` is treated as an aggregated repo.
      # `devshell` hosts the dev shell; `agent-skill-flake` is the builder
      # library (it supplies the `darwinModules` hook and the dev shell's
      # `devshellSkillsHook` wiring). The dev-shell skill sources are no longer
      # listed here: they live in the runtime `skills-devshell/` sub-flake.
      infrastructureInputs = [
        "self"
        "nixpkgs"
        "systems"
        "flake-parts"
        "treefmt-nix"
        "devshell"
        "gradle2nix"
        "agent-skill-flake"
      ];

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

      # Meta-keys every flake conventionally exports as aliases (`default` is
      # how `nix run github:owner/repo` resolves without `#name`). Aggregating
      # would have every input's `default` shadow the previous — silently —
      # so we strip them before merging. Add other meta-keys here (e.g. `all`)
      # if they start colliding in practice.
      aggregatorMetaKeys = [ "default" ];

      stripAggregatorMeta = attrs: builtins.removeAttrs attrs aggregatorMetaKeys;

      # Pulls one flake-output field (e.g. "packages") from every aggregated
      # input for `system`, with `{ }` if that input doesn't expose the field
      # or doesn't support that system. Plain `//` merge after stripping
      # meta-keys; last input still wins on real-name collisions.
      #
      # Single-package flakes (e.g. `claffeinate`) expose only `default`, so
      # blind stripping would drop them entirely. When an input has *no*
      # other named packages, promote its `default` to the input's name —
      # `packages.<sys>.<input-name>`. Inputs that already expose proper
      # names keep their `default` stripped to avoid noise aliases.
      aggregatedFor =
        field: system:
        lib.foldl'
          (acc: name:
            let
              attrs = aggregatedInputs.${name}.${field}.${system} or { };
              named = stripAggregatorMeta attrs;
              promoted =
                if attrs ? default && named == { }
                then { ${name} = attrs.default; }
                else { };
            in acc // promoted // named
          )
          { }
          (builtins.attrNames aggregatedInputs);

      # Root-side wiring for the runtime `skills-devshell/` sub-flake. The skill
      # set itself (git/GitHub pack + skillspkgs' `authoring` combination + the
      # nix-bump skill from skills-nix) is defined in `skills-devshell/flake.nix`
      # and invoked via `nix run "$PRJ_ROOT/skills-devshell#..."` at runtime, so
      # the skill sources stay out of this root's lock. `devshellSkills.startup`
      # is the reconcile snippet; `devshellSkills.commands` are the repo-agnostic
      # `skills`-category dev-shell commands.
      devshellSkills = agent-skill-flake.lib.devshellSkillsHook { };

    in
    {
      legacyPackages = forAllSystems (
        system: localAttrsFor system // aggregatedFor "legacyPackages" system
      );

      packages = forAllSystems (
        system:
        let
          base =
            lib.filterAttrs (_: lib.isDerivation) (localAttrsFor system)
            // aggregatedFor "packages" system;
          # On Darwin, pin the shim's real-claude lookup to the Homebrew
          # path so GUI-launched callers (JetBrains plugin, Dock, launchd)
          # find a working `claude` without depending on the inherited
          # PATH. Runtime `CLAUDE_NIX_EXECUTABLE=…` still wins.
          homebrewClaude =
            if system == "aarch64-darwin" then "/opt/homebrew/bin/claude"
            else if system == "x86_64-darwin" then "/usr/local/bin/claude"
            else null;
        in
        base
        // lib.optionalAttrs (homebrewClaude != null && base ? claude-in-nix-devshell) {
          claude-in-nix-devshell = base.claude-in-nix-devshell.override {
            realClaude = homebrewClaude;
          };
        }
      );

      # numtide/devshell-backed dev shell. Its install-skills startup hook
      # reconciles the dev-shell skill set (authoring + skills-git pack + the
      # nix-bump skill) at project scope under a single owner by invoking the
      # runtime `skills-devshell/` sub-flake; the `skills`-category commands
      # (purge / lock-bump) come from the same hook. `$PRJ_ROOT` is exported by
      # numtide/devshell, so the system-agnostic `nix run "$PRJ_ROOT/..."`
      # strings work regardless of CWD — no per-system splicing needed.
      devShells = forAllSystems (system: {
        default = inputs.devshell.legacyPackages.${system}.mkShell {
          name = "nur-packages";
          motd = ''
            {bold}{14}🚀 Entering nur-packages dev shell{reset}
            Run {bold}menu{reset} to list available commands.
          '';
          devshell.startup.install-skills.text = devshellSkills.startup;
          commands = devshellSkills.commands;
        };
      });

      # Drop-in nix-darwin module: wires agent-skill-flake's user-activation
      # hook so `darwin-rebuild switch` reconciles `~/.claude/skills/<name>` for
      # every skill the consumer puts in `environment.systemPackages`. Pure
      # enabler — installs nothing on its own. The consumer (e.g. a MyNixOS
      # darwin module) lists which packages to install, just like any other
      # package; agent-skill-flake's auto-discovery picks up the ones carrying
      # `passthru.isFlakeSkill` (set by `agent-skill-flake.lib.mkSkillFlake`)
      # and ignores the rest.
      #
      # Consume with:
      #     imports = [ inputs.nur-packages.darwinModules.default ];
      #     environment.systemPackages = with inputs.nur-packages.packages.${pkgs.system}; [
      #       agent-skill-git-branch-naming
      #       agent-skill-nix-flakes
      #       # ...etc — listed explicitly, never auto-populated
      #     ];
      darwinModules.default = { lib, ... }: {
        imports = [ agent-skill-flake.darwinModules.default ];
        services.agent-skill-flake.enable = lib.mkDefault true;
      };
    };
}
