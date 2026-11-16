# nur-packages

A personal NUR repository and package aggregator. `default.nix` exposes the NUR-style attrset, `ci.nix` filters it for CI, and package sources live under `pkgs/<category>/<name>/`. `flake.nix` also re-exports the packages and the Home Manager and nix-darwin modules of the repositories it takes as inputs, and exports the `background-items` nix-darwin module under `modules/`.

## Build and test

`nix develop` enters the dev shell, which installs the project's skills into `.agents/skills/` from the `skills-devshell/` sub-flake and puts these commands on the `PATH`; `menu` lists them all.

- `nur-packages list`: the packages this flake exposes for this machine's system (`--system <system>` for another).
- `nur-packages build <package>...`: builds packages.
- `check`: runs `nix flake check`: formatting, `lib/aggregated-for.nix`'s merge rules, and `nur-packages`' shellcheck and bats checks under `tests/nur-packages/` on every system; on Darwin also builds `background-items` and runs its checks under `tests/background-items/`.
- `fmt`: formats the tree with treefmt.
- `update-flake`: updates `flake.lock`.
