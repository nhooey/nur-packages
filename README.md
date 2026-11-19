# nhooey/nur-packages

Personal [NUR](https://github.com/nix-community/NUR) repository.
Layout follows the [`nur-packages-template`](https://github.com/nix-community/nur-packages-template) conventions: `default.nix` exposes the NUR-style attrset, `ci.nix` filters it to buildable / cacheable derivations for CI, and per-package sources live under `pkgs/<category>/<name>/`.

This flake also acts as an **aggregator**: each input listed in `flake.nix` (other than the infrastructure inputs `nixpkgs`, `systems`, `flake-parts`, `treefmt-nix`, `devshell`, `gradle2nix` and `agent-skill-flake`) contributes its `packages.<system>` and `legacyPackages.<system>` outputs to this flake's, so every downstream package is reachable through one URL.

## Use

### As a flake

```sh
nix run github:nhooey/nur-packages#xtdb
nix build github:nhooey/nur-packages#agent-skill-nhooey-git-hygiene-branch-naming
```

`nix flake show github:nhooey/nur-packages` lists everything currently exposed.

### Via NUR

```nix
{ pkgs ? import <nixpkgs> { } }:
pkgs.nur.repos.nhooey.xtdb
```

Requires [NUR](https://github.com/nix-community/NUR#installation) to be set up in your `nixpkgs` config.

### Without flakes

```nix
(import (fetchTarball "https://github.com/nhooey/nur-packages/archive/master.tar.gz") {
  inherit pkgs;
  buildGradlePackage = …;  # required only for gradle2nix-backed packages (e.g. xtdb)
}).xtdb
```

## Aggregated repos

| Input          | Source                                                                                 |
|----------------|----------------------------------------------------------------------------------------|
| `claude-in-nix-devshell` | [`nhooey/claude-in-nix-devshell`](https://github.com/nhooey/claude-in-nix-devshell) |
| `cljfmt`       | [`nhooey/nix-cljfmt`](https://github.com/nhooey/nix-cljfmt)                            |
| `jellyfin-settings` | [`nhooey/jellyfin-settings`](https://github.com/nhooey/jellyfin-settings) (also re-exports its Home Manager module as `homeModules.jellyfin-settings`) |
| `nix-devshell-cached-exports` | [`nhooey/nix-devshell-cached-exports`](https://github.com/nhooey/nix-devshell-cached-exports) |
| `nix-jetbrains-project-setup` | [`nhooey/nix-jetbrains-project-setup`](https://github.com/nhooey/nix-jetbrains-project-setup) (also re-exports its Home Manager module as `homeModules.nix-jetbrains-project-setup`) |
| `skillspkgs`   | [`nhooey/skillspkgs`](https://github.com/nhooey/skillspkgs) (re-aggregates nix-gstack, git-skills, nix-skills, and third-party skill wrappers) |

Adding another aggregated repo is a one-input edit to `flake.nix`; see the header comment there for the recipe.
Last-write-wins on name collisions.

## nix-darwin modules

| Module                             | What it does                                                                                     |
|------------------------------------|--------------------------------------------------------------------------------------------------|
| `darwinModules.default`            | Wires agent-skill-flake's skill reconcile into activation                                        |
| `darwinModules.nix-devshell-cached-exports` | Weekly `nix-devshell-cached-exports --prune` (re-exported)                              |
| `darwinModules.background-items`   | `services.background-items` ([`modules/background-items`](modules/background-items/default.nix)): keeps the launchd jobs it lists on, off or absent and leaves every other job alone; keeps a list of apps open at login; names nix-darwin's own jobs in System Settings' Login Items list. `background-items --check` reports drift. |

`nix flake check` runs the formatting check, the aggregation merge-rule check (`lib/aggregated-for.nix`) and the `nur-packages` command's shellcheck and bats checks on every system, and on Darwin also the `background-items` checks (module evaluation with its activation scripts run, shellcheck, and a bats suite against stubbed `launchctl`/`osascript`).

## Development

`nix develop` enters the dev shell; `menu` lists its commands.
`nur-packages list` and `nur-packages build <package>...` list and build this flake's packages, `check` runs `nix flake check`, and `fmt` formats the tree.
