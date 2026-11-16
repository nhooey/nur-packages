#!/usr/bin/env bats
# Unit tests for tools/nur-packages/nur-packages.sh, with nix replaced by
# ./stubs/nix (which logs each call to $STUB_LOG, one per line). NP_SCRIPT
# names the script under test; it defaults to the source file.

setup() {
  here=$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)
  script=${NP_SCRIPT:-$here/../../tools/nur-packages/nur-packages.sh}
  PATH=$here/stubs:$PATH
  export STUB_LOG=$BATS_TEST_TMPDIR/log
  export STUB_SYSTEM=x86_64-linux
  export PRJ_ROOT=/repo
  : >"$STUB_LOG"
}

@test "no command is a usage error" {
  run bash "$script"
  [ "$status" -eq 2 ]
  [[ $output == *"name a command"* ]]
  [[ $output == *"Usage: nur-packages <command>"* ]]
}

@test "an unknown command is a usage error" {
  run bash "$script" frobnicate
  [ "$status" -eq 2 ]
  [[ $output == *"unknown command 'frobnicate'"* ]]
}

@test "--help lists every command token and runs no nix" {
  run bash "$script" --help
  [ "$status" -eq 0 ]
  [[ $output == *"  list "* ]]
  [[ $output == *"  build "* ]]
  [ ! -s "$STUB_LOG" ]
}

@test "each command's --help lists its options" {
  run bash "$script" list --help
  [ "$status" -eq 0 ]
  [[ $output == *"--system <system>"* ]]
  run bash "$script" build -h
  [ "$status" -eq 0 ]
  [[ $output == *"--no-link"* ]]
  [ ! -s "$STUB_LOG" ]
}

@test "list prints the packages of this machine's system" {
  export STUB_EVAL=$'alpha\nbeta\n'
  run bash "$script" list
  [ "$status" -eq 0 ]
  [ "$output" = $'alpha\nbeta' ]
  [ "$(sed -n 1p "$STUB_LOG")" = "eval --impure --raw --expr builtins.currentSystem" ]
  [[ $(sed -n 2p "$STUB_LOG") == "eval --raw /repo#packages.x86_64-linux --apply "* ]]
}

@test "list --system names the system and skips asking nix for it" {
  run bash "$script" list --system aarch64-darwin
  [ "$status" -eq 0 ]
  ! grep -q builtins.currentSystem "$STUB_LOG"
  grep -q '^eval --raw /repo#packages.aarch64-darwin ' "$STUB_LOG"
  run bash "$script" list --system=x86_64-darwin
  grep -q '^eval --raw /repo#packages.x86_64-darwin ' "$STUB_LOG"
}

@test "list --system without a value is a usage error" {
  run bash "$script" list --system
  [ "$status" -eq 2 ]
  [[ $output == *"--system needs a value"* ]]
}

@test "list rejects a stray argument" {
  run bash "$script" list xtdb
  [ "$status" -eq 2 ]
  [[ $output == *"unexpected argument 'xtdb'"* ]]
}

@test "build with no package is a usage error and runs no nix" {
  run bash "$script" build
  [ "$status" -eq 2 ]
  [[ $output == *"name at least one package"* ]]
  [ ! -s "$STUB_LOG" ]
}

@test "build rejects an unknown option" {
  run bash "$script" build --fast xtdb
  [ "$status" -eq 2 ]
  [[ $output == *"unknown option '--fast'"* ]]
}

@test "build builds every package in one nix call from the repository root" {
  run bash "$script" build xtdb background-items
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_LOG")" = "build /repo#xtdb /repo#background-items" ]
}

@test "build passes --no-link and everything after -- to nix" {
  run bash "$script" build --no-link xtdb -- -L --keep-going
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_LOG")" = "build /repo#xtdb --no-link -L --keep-going" ]
}

@test "build exits with nix's status when nix fails" {
  export STUB_STATUS=7
  run bash "$script" build xtdb
  [ "$status" -eq 7 ]
}
