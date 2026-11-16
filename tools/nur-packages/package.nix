# The dev shell's `nur-packages` command (see nur-packages.sh). It runs the
# nix and git already on the PATH, so it builds with the same nix the shell
# was entered with.
{ writeShellApplication }:
writeShellApplication {
  name = "nur-packages";
  text = builtins.readFile ./nur-packages.sh;
  meta = {
    description = "List and build the packages the nur-packages flake exposes";
    mainProgram = "nur-packages";
  };
}
