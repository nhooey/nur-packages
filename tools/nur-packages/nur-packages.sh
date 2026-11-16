#!/usr/bin/env bash
# nur-packages: list and build the packages this flake exposes, from the
# repository root wherever it is run. Exits 0 on success, 2 on a usage
# error, and with nix's status when nix fails.

set -euo pipefail

prog=nur-packages

usage() {
  cat <<EOF
Usage: $prog <command> [options]

List and build the packages this flake exposes, including the ones its
aggregated inputs contribute.

Commands:
  list    List the package names for a system
  build   Build one or more packages

Options:
  -h, --help  Show this help, or a command's with '$prog <command> --help'

The dev shell's 'check', 'fmt' and 'update-flake' commands run the flake's
checks, format the tree and update flake.lock.
EOF
}

usage_list() {
  cat <<EOF
Usage: $prog list [--system <system>]

Print the name of each package in packages.<system>, one per line.

Options:
  -s, --system <system>  The system to list (default: this machine's)
  -h, --help             Show this help
EOF
}

usage_build() {
  cat <<EOF
Usage: $prog build [--no-link] <package>... [-- <nix build option>...]

Build each named package with 'nix build'. The result links land in the
current folder unless --no-link is given.

Options:
  --no-link   Leave no result links
  -h, --help  Show this help
EOF
}

# die_usage MESSAGE USAGE_FUNCTION: report a usage error and exit 2.
die_usage() {
  echo "$prog: $1" >&2
  "$2" >&2
  exit 2
}

# The repository root: the dev shell's PRJ_ROOT, else the enclosing git
# work tree.
repo_root() {
  if [ -n "${PRJ_ROOT:-}" ]; then
    printf '%s\n' "$PRJ_ROOT"
  elif git rev-parse --show-toplevel 2>/dev/null; then
    :
  else
    echo "$prog: not in the dev shell or a git work tree" >&2
    exit 1
  fi
}

cmd_list() {
  local system=""
  while [ $# -gt 0 ]; do
    case $1 in
    -h | --help)
      usage_list
      return 0
      ;;
    -s | --system)
      [ $# -ge 2 ] || die_usage "$1 needs a value" usage_list
      system=$2
      shift 2
      ;;
    --system=*)
      system=${1#--system=}
      shift
      ;;
    *) die_usage "list: unexpected argument '$1'" usage_list ;;
    esac
  done
  [ -n "$system" ] || system=$(nix eval --impure --raw --expr builtins.currentSystem)

  local root
  root=$(repo_root)
  nix eval --raw "$root#packages.$system" \
    --apply 'packages: builtins.concatStringsSep "\n" (builtins.attrNames packages) + "\n"'
}

cmd_build() {
  local packages=() nix_args=()
  while [ $# -gt 0 ]; do
    case $1 in
    -h | --help)
      usage_build
      return 0
      ;;
    --no-link)
      nix_args+=(--no-link)
      shift
      ;;
    --)
      shift
      nix_args+=("$@")
      break
      ;;
    -*) die_usage "build: unknown option '$1'" usage_build ;;
    *)
      packages+=("$1")
      shift
      ;;
    esac
  done
  [ ${#packages[@]} -gt 0 ] || die_usage "build: name at least one package" usage_build

  local root installables=() package
  root=$(repo_root)
  for package in "${packages[@]}"; do
    installables+=("$root#$package")
  done
  nix build "${installables[@]}" "${nix_args[@]}"
}

main() {
  [ $# -gt 0 ] || die_usage "name a command" usage
  local command=$1
  shift
  case $command in
  -h | --help) usage ;;
  list) cmd_list "$@" ;;
  build) cmd_build "$@" ;;
  *) die_usage "unknown command '$command'" usage ;;
  esac
}

main "$@"
