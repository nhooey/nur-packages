# nur-packages

A personal NUR repository and package aggregator. `default.nix` exposes the NUR-style attrset, `ci.nix` filters it for CI, and package sources live under `pkgs/<category>/<name>/`. `flake.nix` also re-exports the packages of the repositories it takes as inputs, and the Home Manager and nix-darwin modules under `modules/`.

## Build and test

- `nix develop`: the dev shell, with the project's skills installed into `.agents/skills/` from the `skills-devshell/` sub-flake.
- `nix build .#<package>`: builds one package; `nix flake show` lists them.
- `nix flake check`: on Darwin, builds `background-items` and runs its shellcheck and bats checks under `tests/background-items/`.
