#!/usr/bin/env bash
# background-items: keep the launchd jobs and Open-at-Login apps named in
# services.background-items (a nix-darwin module) in their configured state,
# and report drift. Every job, file and login item the configuration does not
# name is left alone.
#
# The configuration is a JSON file written by the module (default
# /etc/background-items/config.json):
#   {
#     "user": "alice", "uid": 501 | null, "home": "/Users/alice",
#     "dirs": { "gui": [ "<home>/Library/LaunchAgents", "/Library/LaunchAgents" ],
#               "system": [ "/Library/LaunchDaemons" ] },
#     "items": [ { "label": "...", "state": "on" | "off" | "absent",
#                  "domain": "gui" | "system", "plists": [ "<exact path>", ... ],
#                  "extraPaths": [ "<exact path>", ... ] } ],
#     "openAtLogin": [ "/Applications/Foo.app" ],
#     "loginItemsState": "<home>/Library/Application Support/background-items/open-at-login"
#   }
#
# The macOS tools it drives can be swapped out (for the tests) with
# BI_LAUNCHCTL, BI_SFLTOOL, BI_OSASCRIPT and BI_SUDO.
set -euo pipefail

: "${BI_LAUNCHCTL:=/bin/launchctl}"
: "${BI_OSASCRIPT:=/usr/bin/osascript}"
: "${BI_SUDO:=/usr/bin/sudo}"
config=${BACKGROUND_ITEMS_CONFIG:-/etc/background-items/config.json}

usage() {
  cat <<'EOF'
Usage: background-items [--config FILE] COMMAND

Commands:
  --check, check     Report listed launchd jobs whose state differs from the
                     configuration (exit 1 if any), then, for information
                     only, the jobs the configuration does not list. Run with
                     sudo to include the Background Task Management database
                     (sfltool dumpbtm) in the untracked list.
  apply              Bring every listed job to its state and update the
                     Open-at-Login list (run as root, by activation).
  cleanup            Re-run only the "absent" removals (run as root, by the
                     WatchPaths job).
  login-items        Update the Open-at-Login list (run as the user, in the
                     user's GUI session).
  install-launchers --dir DIR --source FILE [NAME...]
                     Copy FILE to DIR/NAME for each NAME, and remove the
                     names an earlier run installed that are no longer listed.
EOF
}

warn() { printf 'background-items: %s\n' "$*" >&2; }

# --- configuration ----------------------------------------------------------

cfg() { jq -r "$@" "$config"; }

user_name() { cfg '.user'; }
user_home() { cfg '.home'; }

user_uid() {
  local uid
  uid=$(cfg '.uid // empty')
  if [ -z "$uid" ]; then
    uid=$(id -u -- "$(user_name)")
  fi
  printf '%s\n' "$uid"
}

# One line per item: label, state, domain (tab-separated).
items() { cfg '.items[] | [.label, .state, .domain] | @tsv'; }

item_plists() { jq -r --arg l "$1" '.items[] | select(.label == $l) | .plists[]' "$config"; }
item_extra_paths() { jq -r --arg l "$1" '.items[] | select(.label == $l) | .extraPaths[]' "$config"; }

domain_target() {
  case $1 in
  system) printf 'system\n' ;;
  gui) printf 'gui/%s\n' "$(user_uid)" ;;
  *)
    warn "unknown domain: $1"
    return 1
    ;;
  esac
}

# --- launchd ----------------------------------------------------------------

is_loaded() { "$BI_LAUNCHCTL" print "$1/$2" >/dev/null 2>&1; }

# The labels `launchctl print-disabled DOMAIN` lists as disabled. macOS 14+
# prints `"label" => disabled`, older releases `"label" => true`.
disabled_labels() {
  "$BI_LAUNCHCTL" print-disabled "$1" 2>/dev/null |
    sed -n -E 's/^[[:space:]]*"([^"]+)"[[:space:]]*=>[[:space:]]*(disabled|true)[[:space:]]*$/\1/p'
}

is_disabled() { disabled_labels "$1" | grep -qxF -- "$2"; }

first_existing_plist() {
  local p
  while IFS= read -r p; do
    if [ -f "$p" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  done < <(item_plists "$1")
  return 1
}

# An extra path must be absolute, below the top level and free of `.`/`..`
# components: it is deleted recursively. The module checks the same at
# evaluation time.
safe_path() {
  local p=$1
  case $p in
  /*/*) ;;
  *) return 1 ;;
  esac
  case "$p/" in
  */./* | */../* | *//*) return 1 ;;
  esac
  return 0
}

apply_on() {
  local label=$1 domain=$2 plist
  "$BI_LAUNCHCTL" enable "$domain/$label" || warn "$label: launchctl enable failed"
  if plist=$(first_existing_plist "$label") && ! is_loaded "$domain" "$label"; then
    "$BI_LAUNCHCTL" bootstrap "$domain" "$plist" ||
      warn "$label: launchctl bootstrap $domain $plist failed"
  fi
}

apply_off() {
  local label=$1 domain=$2
  "$BI_LAUNCHCTL" disable "$domain/$label" || warn "$label: launchctl disable failed"
  if is_loaded "$domain" "$label"; then
    "$BI_LAUNCHCTL" bootout "$domain/$label" || warn "$label: launchctl bootout failed"
  fi
}

apply_absent() {
  local label=$1 domain=$2 p
  if is_loaded "$domain" "$label"; then
    "$BI_LAUNCHCTL" bootout "$domain/$label" || warn "$label: launchctl bootout failed"
  fi
  while IFS= read -r p; do
    if [ -e "$p" ] || [ -L "$p" ]; then
      printf 'background-items: %s: removing %s\n' "$label" "$p"
      rm -f -- "$p" || warn "$label: could not remove $p"
    fi
  done < <(item_plists "$label")
  while IFS= read -r p; do
    if ! safe_path "$p"; then
      warn "$label: refusing to remove unsafe path: $p"
    elif [ -e "$p" ] || [ -L "$p" ]; then
      printf 'background-items: %s: removing %s\n' "$label" "$p"
      rm -rf -- "$p" || warn "$label: could not remove $p"
    fi
  done < <(item_extra_paths "$label")
}

# Apply every item, or with `absent` only the absent ones.
apply_items() {
  local only=${1:-} label state domain target
  while IFS=$'\t' read -r label state domain; do
    [ -n "$label" ] || continue
    if [ -n "$only" ] && [ "$state" != "$only" ]; then continue; fi
    target=$(domain_target "$domain") || continue
    case $state in
    on) apply_on "$label" "$target" ;;
    off) apply_off "$label" "$target" ;;
    absent) apply_absent "$label" "$target" ;;
    *) warn "$label: unknown state: $state" ;;
    esac
  done < <(items)
}

# --- Open at Login ----------------------------------------------------------

login_items_list() {
  "$BI_OSASCRIPT" <<'EOF'
tell application "System Events"
  set out to ""
  repeat with i in login items
    set out to out & (path of i) & linefeed
  end repeat
end tell
return out
EOF
}

login_item_add() {
  "$BI_OSASCRIPT" - "$1" <<'EOF'
on run argv
  tell application "System Events" to make login item at end with properties {path:(item 1 of argv), hidden:false}
end run
EOF
}

login_item_remove() {
  "$BI_OSASCRIPT" - "$1" <<'EOF'
on run argv
  tell application "System Events" to delete (every login item whose path is (item 1 of argv))
end run
EOF
}

strip_slash() { sed -E 's:/+$::'; }

# Adds the listed apps that are not login items yet, and removes the ones an
# earlier run added that are no longer listed. Login items this command did
# not add are never removed: an app that was already a login item is not
# recorded as added.
login_items() {
  local state_file desired current added kept p
  state_file=$(cfg '.loginItemsState')
  desired=$(cfg '.openAtLogin[]' | strip_slash)
  added=""
  if [ -f "$state_file" ]; then added=$(strip_slash <"$state_file"); fi
  if [ -z "$desired" ] && [ -z "$added" ]; then return 0; fi

  current=$(login_items_list | strip_slash) || {
    warn "could not read login items (System Events)"
    return 0
  }
  kept=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if grep -qxF -- "$p" <<<"$current"; then
      # Keep tracking it only if this command added it.
      if grep -qxF -- "$p" <<<"$added"; then kept+="$p"$'\n'; fi
    elif [ ! -e "$p" ]; then
      warn "open at login: $p does not exist; skipping"
    elif login_item_add "$p" >/dev/null; then
      printf 'background-items: open at login: added %s\n' "$p"
      kept+="$p"$'\n'
    else
      warn "open at login: could not add $p"
    fi
  done <<<"$desired"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    grep -qxF -- "$p" <<<"$desired" && continue
    if grep -qxF -- "$p" <<<"$current"; then
      if login_item_remove "$p" >/dev/null; then
        printf 'background-items: open at login: removed %s\n' "$p"
      else
        warn "open at login: could not remove $p"
        kept+="$p"$'\n'
      fi
    fi
  done <<<"$added"
  mkdir -p -- "$(dirname -- "$state_file")"
  printf '%s' "$kept" >"$state_file"
}

# Runs login-items as the user inside the user's GUI session, where System
# Events is reachable; skipped while the user is not logged in.
login_items_as_user() {
  local uid user self
  uid=$(user_uid)
  user=$(user_name)
  self=$(command -v "$0" || printf '%s' "$0")
  if [ "$(cfg '(.openAtLogin | length) + 0')" = 0 ] && [ ! -f "$(cfg '.loginItemsState')" ]; then
    return 0
  fi
  if ! "$BI_LAUNCHCTL" print "gui/$uid" >/dev/null 2>&1; then
    warn "open at login: $user has no GUI session; skipping until the next activation"
    return 0
  fi
  "$BI_LAUNCHCTL" asuser "$uid" "$BI_SUDO" --user="$user" -- "$self" --config "$config" login-items ||
    warn "open at login: update failed"
}

# --- launchers --------------------------------------------------------------

valid_launcher_name() {
  case $1 in
  "" | . | .. | .* | */* | *$'\n'*) return 1 ;;
  esac
}

install_launchers() {
  local dir="" source="" manifest name old tmp
  while [ $# -gt 0 ]; do
    case $1 in
    --dir)
      dir=$2
      shift 2
      ;;
    --source)
      source=$2
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *) break ;;
    esac
  done
  if [ -z "$dir" ] || [ -z "$source" ]; then
    warn "install-launchers needs --dir and --source"
    return 2
  fi
  manifest="$dir/.managed-by-background-items"
  if [ -L "$dir" ]; then
    warn "$dir is a symlink; not installing launchers"
    return 1
  fi
  if [ $# -eq 0 ] && [ ! -f "$manifest" ]; then return 0; fi
  mkdir -p -- "$dir"
  for name in "$@"; do
    if ! valid_launcher_name "$name"; then
      warn "invalid launcher name: $name"
      return 1
    fi
  done
  # A copy, not a symlink into /nix/store: daemons start before /nix is
  # mounted. Written beside the target and renamed over it, so a job that is
  # starting never sees a partly written file.
  for name in "$@"; do
    tmp="$dir/.$name.tmp"
    cp -f -- "$source" "$tmp"
    chmod 0555 "$tmp"
    if [ "$(id -u)" = 0 ]; then chown root:wheel "$tmp"; fi
    mv -f -- "$tmp" "$dir/$name"
  done
  if [ -f "$manifest" ]; then
    while IFS= read -r old; do
      valid_launcher_name "$old" || continue
      if ! printf '%s\n' "$@" | grep -qxF -- "$old"; then
        printf 'background-items: removing launcher %s\n' "$dir/$old"
        rm -f -- "${dir:?}/$old"
      fi
    done <"$manifest"
  fi
  if [ $# -eq 0 ]; then
    rm -f -- "$manifest"
  else
    printf '%s\n' "$@" >"$manifest"
  fi
}

# --- check ------------------------------------------------------------------

# Identifiers of the launchd jobs and login items in the Background Task
# Management database. `sfltool dumpbtm` needs root; without it this prints
# nothing. Some identifiers carry a `<number>.` type prefix, which is dropped.
btm_identifiers() {
  local sfltool=${BI_SFLTOOL:-}
  if [ -z "$sfltool" ]; then
    [ "$(id -u)" = 0 ] || return 0
    sfltool=/usr/bin/sfltool
  fi
  "$sfltool" dumpbtm 2>/dev/null |
    sed -n -E 's/^[[:space:]]*Identifier:[[:space:]]*(.+)$/\1/p' |
    sed -E 's/^[0-9]+\.//; s/[[:space:]]+$//' |
    grep -v -e '^Unknown' -e '^$' || true
}

plist_labels_in_dirs() {
  local d f
  while IFS= read -r d; do
    [ -d "$d" ] || continue
    for f in "$d"/*.plist; do
      [ -e "$f" ] || continue
      f=${f##*/}
      printf '%s\n' "${f%.plist}"
    done
  done < <(cfg '.dirs[][]')
}

check() {
  local label state domain target drift=0 problems p listed untracked
  printf 'Listed items whose state differs from the configuration:\n'
  while IFS=$'\t' read -r label state domain; do
    [ -n "$label" ] || continue
    target=$(domain_target "$domain") || continue
    problems=()
    case $state in
    on)
      if is_disabled "$target" "$label"; then problems+=("disabled"); fi
      if first_existing_plist "$label" >/dev/null; then
        is_loaded "$target" "$label" || problems+=("not loaded")
      fi
      ;;
    off)
      is_disabled "$target" "$label" || problems+=("not disabled")
      if is_loaded "$target" "$label"; then problems+=("loaded"); fi
      ;;
    absent)
      if is_loaded "$target" "$label"; then problems+=("loaded"); fi
      while IFS= read -r p; do
        if [ -e "$p" ] || [ -L "$p" ]; then problems+=("$p exists"); fi
      done < <(
        item_plists "$label"
        item_extra_paths "$label"
      )
      ;;
    esac
    if [ ${#problems[@]} -gt 0 ]; then
      drift=1
      printf '  %s (%s, want %s): %s\n' "$label" "$domain" "$state" \
        "$(printf '%s\n' "${problems[@]}" | paste -sd ',' - | sed 's/,/, /g')"
    fi
  done < <(items)
  if [ "$drift" = 0 ]; then printf '  (none)\n'; fi

  listed=$(cfg '.items[].label')
  untracked=$({
    plist_labels_in_dirs
    btm_identifiers
  } | sort -u | grep -vxF -f <(printf '%s\n' "$listed") || true)
  printf '\nUntracked (not in services.background-items.items; informational):\n'
  if [ -n "$untracked" ]; then
    while IFS= read -r p; do printf '  %s\n' "$p"; done <<<"$untracked"
  else
    printf '  (none)\n'
  fi
  if [ "$(id -u)" != 0 ] && [ -z "${BI_SFLTOOL:-}" ]; then
    printf '  (run with sudo to include the Background Task Management database)\n'
  fi
  return "$drift"
}

# --- main -------------------------------------------------------------------

while [ $# -gt 0 ]; do
  case $1 in
  --config)
    config=$2
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) break ;;
  esac
done

command=${1:-}
[ $# -gt 0 ] && shift
case $command in
--check | check) check ;;
apply)
  apply_items
  login_items_as_user
  ;;
cleanup) apply_items absent ;;
login-items) login_items ;;
install-launchers) install_launchers "$@" ;;
*)
  usage >&2
  exit 2
  ;;
esac
