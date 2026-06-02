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

    claffeinate = {
      url = "github:nhooey/claffeinate";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-in-nix-devshell = {
      url = "github:nhooey/claude-in-nix-devshell";
      inputs.nixpkgs.follows = "nixpkgs";
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
    # repo — it exposes `darwinModules` / `lib`, no `packages`.
    flake-skills = {
      url = "github:nhooey/flake-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    gradle2nix = {
      url = "github:nhooey/gradle2nix/v2_bugfix-remove-param-console-plain";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Aggregates nhooey/{nix-gstack, skills-git, skills-nix} and the
    # third-party skill wrappers under `skillspkgs/pkgs/`. We rely on
    # skillspkgs to forward those packages instead of importing each
    # repo as a direct input here.
    skillspkgs = {
      url = "github:nhooey/skillspkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      # Pin skillspkgs's flake-skills to the top-level one so the home-
      # manager activation module (from top-level flake-skills) and the
      # skill derivations (built under skillspkgs's flake-skills) share a
      # single rev and agree on their `passthru` contract. skillspkgs
      # itself follows its own flake-skills into skills-git / skills-nix,
      # so this one override propagates through the whole tree.
      inputs.flake-skills.follows = "flake-skills";
    };

    # The skills-git pack installed into this repo's dev shell at project
    # scope. Listed as infrastructure (see `infrastructureInputs` below) so
    # its packages are NOT auto-aggregated — they already reach this flake
    # transitively via skillspkgs.
    skills-git = {
      url = "github:nhooey/skills-git";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-skills.follows = "flake-skills";
      };
    };

    # skillspkgs' curated `authoring` combination (nix-*, humanizer,
    # skill-creator, superpowers), pulled at `?dir=sources/combinations` so
    # only the combination-builder eval is fetched. Infrastructure-only —
    # combinations are deliberately kept out of `packages.<sys>` upstream
    # and we don't want to aggregate the helper outputs either.
    skillspkgs-combinations = {
      url = "github:nhooey/skillspkgs?dir=sources/combinations";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-skills.follows = "flake-skills";
      };
    };
  };

  outputs =
    { self, nixpkgs, gradle2nix, flake-skills, ... }@inputs:
    let
      lib = nixpkgs.lib;

      # Inputs that power this flake itself, not downstream package repos.
      # Everything else in `inputs` is treated as an aggregated repo.
      # `devshell` / `skills-git` / `skillspkgs-combinations` power the dev
      # shell only — skills-git's packages already reach us transitively via
      # skillspkgs, and the combinations / mkShell helpers shouldn't appear
      # under `packages.<sys>` anyway.
      infrastructureInputs = [
        "self"
        "nixpkgs"
        "devshell"
        "gradle2nix"
        "flake-skills"
        "skills-git"
        "skillspkgs-combinations"
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

      # numtide/devshell-backed dev shell with two startup hooks that
      # reconcile the skills-git pack and skillspkgs' curated `authoring`
      # combination at project scope. Mirrors the canonical idiom in
      # nhooey/skills-git's dev shell.
      devShells = forAllSystems (system: {
        default = inputs.devshell.legacyPackages.${system}.mkShell {
          name = "nur-packages";
          motd = ''
            {bold}{14}🚀 Entering nur-packages dev shell{reset}
            Run {bold}menu{reset} to list available commands.
          '';
          devshell.startup.install-git-skills.text = ''
            ${inputs.skills-git.reconcileScript system}
          '';
          devshell.startup.install-authoring-skills.text = ''
            ${inputs.skillspkgs-combinations.combinations.authoring.${system}.reconcileScript}
          '';
        };
      });

      # Drop-in nix-darwin module: wires flake-skills' user-activation hook
      # so `darwin-rebuild switch` reconciles `~/.claude/skills/<name>` for
      # every skill the consumer puts in `environment.systemPackages`. Pure
      # enabler — installs nothing on its own. The consumer (e.g. a MyNixOS
      # darwin module) lists which packages to install, just like any other
      # package; flake-skills' auto-discovery picks up the ones carrying
      # `passthru.isFlakeSkill` (set by `flake-skills.lib.mkSkillFlake`) and
      # ignores the rest.
      #
      # Consume with:
      #     imports = [ inputs.nur-packages.darwinModules.default ];
      #     environment.systemPackages = with inputs.nur-packages.packages.${pkgs.system}; [
      #       agent-skill-git-branch-naming
      #       agent-skill-nix-flakes
      #       # ...etc — listed explicitly, never auto-populated
      #     ];
      darwinModules.default = { lib, ... }: {
        imports = [ flake-skills.darwinModules.default ];
        services.flake-skills.enable = lib.mkDefault true;
      };
    };
}
