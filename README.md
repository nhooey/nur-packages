# nhooey/nur-packages

[![built with garnix](https://img.shields.io/endpoint.svg?url=https%3A%2F%2Fgarnix.io%2Fapi%2Fbadges%2Fnhooey%2Fnur-packages)](https://garnix.io/repo/nhooey/nur-packages)

Personal [NUR](https://github.com/nix-community/NUR) repository. Layout follows
the [`nur-packages-template`](https://github.com/nix-community/nur-packages-template)
conventions: `default.nix` exposes the NUR-style attrset, `ci.nix` filters it
to buildable / cacheable derivations for CI, and per-package sources live under
`pkgs/<category>/<name>/`.

This flake also acts as an **aggregator**: each input listed in `flake.nix` (other
than the infrastructure inputs `nixpkgs` and `gradle2nix`) contributes its
`packages.<system>` and `legacyPackages.<system>` outputs to this flake's, so
every downstream package is reachable through one URL.

## Use

### As a flake

```sh
nix run github:nhooey/nur-packages#xtdb
nix build github:nhooey/nur-packages#skill-git
```

`nix flake show github:nhooey/nur-packages` lists everything currently exposed.

### Via NUR

```nix
{ pkgs ? import <nixpkgs> { } }:
pkgs.nur.repos.nhooey.xtdb
```

Requires [NUR](https://github.com/nix-community/NUR#installation) to be set up
in your `nixpkgs` config.

### Without flakes

```nix
(import (fetchTarball "https://github.com/nhooey/nur-packages/archive/master.tar.gz") {
  inherit pkgs;
  buildGradlePackage = …;  # required only for gradle2nix-backed packages (e.g. xtdb)
}).xtdb
```

## Aggregated repos

| Input          | Source                                                                 |
|----------------|------------------------------------------------------------------------|
| `gradle2nix`   | [`nhooey/gradle2nix`](https://github.com/nhooey/gradle2nix) (fork)     |
| `skills-git`   | [`nhooey/skills-git`](https://github.com/nhooey/skills-git)            |
| `skills-nix`   | [`nhooey/skills-nix`](https://github.com/nhooey/skills-nix)            |
| `claffeinate`  | [`nhooey/claffeinate`](https://github.com/nhooey/claffeinate) (Darwin) |
| `nix-gstack`   | [`nhooey/nix-gstack`](https://github.com/nhooey/nix-gstack)            |

Adding another aggregated repo is a one-input edit to `flake.nix`; see the
header comment there for the recipe. Last-write-wins on name collisions.

## CI

Builds run on [Garnix](https://garnix.io) for every push, across all four
systems (`x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`).
Outputs are cached at `https://cache.garnix.io` (public key
`cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=`); add it as a
substituter to pull binaries instead of rebuilding locally.
