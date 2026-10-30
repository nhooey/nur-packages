# The `background-items` command (see background-items.sh) that
# services.background-items runs on activation, and that `background-items
# --check` reports drift with.
{
  lib,
  writeShellApplication,
  coreutils,
  gnugrep,
  gnused,
  jq,
}:
writeShellApplication {
  name = "background-items";
  runtimeInputs = [
    coreutils
    gnugrep
    gnused
    jq
  ];
  text = builtins.readFile ./background-items.sh;
  meta = {
    description = "Keep listed macOS launchd jobs and login items in a configured state";
    platforms = lib.platforms.darwin;
    mainProgram = "background-items";
  };
}
