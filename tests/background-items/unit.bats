#!/usr/bin/env bats
# Unit tests for modules/background-items/background-items.sh, run against a
# temporary HOME and root folder, with launchctl, osascript, sudo and sfltool
# replaced by the stubs in ./stubs (which log to $STUB_LOG and keep their
# state in $STUB_STATE). BI_SCRIPT names the script under test; it defaults
# to the source file.

setup() {
  here=$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)
  script=${BI_SCRIPT:-$here/../../modules/background-items/background-items.sh}
  export BI_LAUNCHCTL=$here/stubs/launchctl
  export BI_OSASCRIPT=$here/stubs/osascript
  export BI_SUDO=$here/stubs/sudo
  export BI_TEST_FIXTURES=$here/fixtures
  export STUB_STATE=$BATS_TEST_TMPDIR/state
  export STUB_LOG=$BATS_TEST_TMPDIR/log
  mkdir -p "$STUB_STATE"
  : >"$STUB_LOG"

  root=$BATS_TEST_TMPDIR/root
  home=$root/Users/alice
  mkdir -p "$home/Library/LaunchAgents" "$root/Library/LaunchAgents" "$root/Library/LaunchDaemons"
  config=$BATS_TEST_TMPDIR/config.json
}

# write_config ITEMS_JSON [OPEN_AT_LOGIN_JSON]: the config file the module
# would write, with the system folders under $root.
write_config() {
  jq -n --arg root "$root" --arg home "$home" --argjson items "$1" --argjson open "${2:-[]}" '{
    user: "alice", uid: 501, home: $home,
    dirs: { gui: [ "\($home)/Library/LaunchAgents", "\($root)/Library/LaunchAgents" ],
            system: [ "\($root)/Library/LaunchDaemons" ] },
    items: $items,
    openAtLogin: $open,
    loginItemsState: "\($home)/Library/Application Support/background-items/open-at-login"
  }' >"$config"
}

gui_item() {
  jq -n --arg root "$root" --arg home "$home" --arg label "$1" --arg state "$2" --argjson extra "${3:-[]}" '{
    label: $label, state: $state, domain: "gui",
    plists: [ "\($home)/Library/LaunchAgents/\($label).plist", "\($root)/Library/LaunchAgents/\($label).plist" ],
    extraPaths: $extra }'
}

system_item() {
  jq -n --arg root "$root" --arg label "$1" --arg state "$2" --argjson extra "${3:-[]}" '{
    label: $label, state: $state, domain: "system",
    plists: [ "\($root)/Library/LaunchDaemons/\($label).plist" ],
    extraPaths: $extra }'
}

bi() { "$script" --config "$config" "$@"; }

@test "absent: boots out and deletes the listed plists and extra paths, nothing else" {
  touch "$home/Library/LaunchAgents/com.google.keystone.agent.plist" \
    "$root/Library/LaunchAgents/com.google.keystone.agent.plist" \
    "$root/Library/LaunchDaemons/com.google.keystone.daemon.plist" \
    "$home/Library/LaunchAgents/com.google.keystone.agent.plist.bak" \
    "$home/Library/LaunchAgents/com.other.agent.plist"
  mkdir -p "$home/Library/Application Support/Google/GoogleUpdater/x" "$root/Library/Google/Other"
  printf 'gui/501/com.google.keystone.agent\nsystem/com.google.keystone.daemon\ngui/501/com.other.agent\n' >"$STUB_STATE/loaded"
  write_config "[$(gui_item com.google.keystone.agent absent "[\"$home/Library/Application Support/Google/GoogleUpdater\"]"),
                 $(system_item com.google.keystone.daemon absent)]"

  run bi apply
  [ "$status" -eq 0 ]
  [ ! -e "$home/Library/LaunchAgents/com.google.keystone.agent.plist" ]
  [ ! -e "$root/Library/LaunchAgents/com.google.keystone.agent.plist" ]
  [ ! -e "$root/Library/LaunchDaemons/com.google.keystone.daemon.plist" ]
  [ ! -e "$home/Library/Application Support/Google/GoogleUpdater" ]
  # Untouched: a similarly named file, an unlisted job, a sibling folder.
  [ -e "$home/Library/LaunchAgents/com.google.keystone.agent.plist.bak" ]
  [ -e "$home/Library/LaunchAgents/com.other.agent.plist" ]
  [ -d "$root/Library/Google/Other" ]
  grep -qxF 'gui/501/com.other.agent' "$STUB_STATE/loaded"
  grep -qxF 'launchctl bootout gui/501/com.google.keystone.agent' "$STUB_LOG"
  grep -qxF 'launchctl bootout system/com.google.keystone.daemon' "$STUB_LOG"
}

@test "absent: refuses an unsafe extra path" {
  write_config "[$(gui_item com.x absent '["/", "/Library", "/a/../b"]')]"
  run bi apply
  [ "$status" -eq 0 ]
  [ "$(grep -c 'refusing to remove unsafe path' <<<"$output")" -eq 3 ]
}

@test "cleanup runs only the absent items" {
  touch "$home/Library/LaunchAgents/com.gone.plist" "$home/Library/LaunchAgents/com.off.plist"
  echo gui/501/com.off >"$STUB_STATE/loaded"
  write_config "[$(gui_item com.gone absent), $(gui_item com.off off)]"
  run bi cleanup
  [ "$status" -eq 0 ]
  [ ! -e "$home/Library/LaunchAgents/com.gone.plist" ]
  grep -qxF 'gui/501/com.off' "$STUB_STATE/loaded"
  ! grep -q 'disable' "$STUB_LOG"
}

@test "off: disables and boots out" {
  touch "$root/Library/LaunchDaemons/com.off.plist"
  echo system/com.off >"$STUB_STATE/loaded"
  write_config "[$(system_item com.off off)]"
  run bi apply
  [ "$status" -eq 0 ]
  grep -qxF 'system/com.off' "$STUB_STATE/disabled"
  ! grep -qxF 'system/com.off' "$STUB_STATE/loaded"
  [ -e "$root/Library/LaunchDaemons/com.off.plist" ]
}

@test "on: enables, and bootstraps from the plist when not loaded" {
  touch "$root/Library/LaunchAgents/com.on.plist"
  echo gui/501/com.on >"$STUB_STATE/disabled"
  write_config "[$(gui_item com.on on), $(gui_item com.on-missing on)]"
  run bi apply
  [ "$status" -eq 0 ]
  ! grep -qxF 'gui/501/com.on' "$STUB_STATE/disabled"
  grep -qxF "launchctl bootstrap gui/501 $root/Library/LaunchAgents/com.on.plist" "$STUB_LOG"
  grep -qxF 'gui/501/com.on' "$STUB_STATE/loaded"
  # No plist: enabled, not bootstrapped.
  grep -qxF 'launchctl enable gui/501/com.on-missing' "$STUB_LOG"
  ! grep -q 'bootstrap gui/501 .*com.on-missing' "$STUB_LOG"
}

@test "check: no drift after apply, exit 0, untracked listed for information" {
  export BI_SFLTOOL=$here/stubs/sfltool
  touch "$home/Library/LaunchAgents/com.google.keystone.agent.plist" \
    "$root/Library/LaunchDaemons/com.off.plist" \
    "$home/Library/LaunchAgents/com.untracked.agent.plist"
  echo system/com.off >"$STUB_STATE/loaded"
  write_config "[$(gui_item com.google.keystone.agent absent), $(system_item com.off off)]"
  bi apply
  run bi --check
  [ "$status" -eq 0 ]
  [[ $output == *"differs from the configuration:"$'\n'"  (none)"* ]]
  [[ $output == *"  com.untracked.agent"* ]]
  [[ $output == *"  com.bjango.istatmenus"* ]]
  [[ $output == *"  org.nixos.nix-gc"* ]]
  # Listed items are not untracked, even when the BTM database has them.
  untracked=${output#*Untracked}
  [[ $untracked != *"com.google.keystone.agent"* ]]
  [[ $untracked != *"com.off"* ]]
}

@test "check: reports drift in listed items and exits 1" {
  touch "$home/Library/LaunchAgents/com.gone.plist" "$root/Library/LaunchDaemons/com.on.plist"
  mkdir -p "$root/Library/Gone/Data"
  printf 'gui/501/com.off\n' >"$STUB_STATE/loaded"
  printf 'system/com.on\n' >"$STUB_STATE/disabled"
  write_config "[$(gui_item com.gone absent "[\"$root/Library/Gone/Data\"]"), $(gui_item com.off off), $(system_item com.on on)]"
  run bi --check
  [ "$status" -eq 1 ]
  [[ $output == *"com.gone (gui, want absent): $home/Library/LaunchAgents/com.gone.plist exists, $root/Library/Gone/Data exists"* ]]
  [[ $output == *"com.off (gui, want off): not disabled, loaded"* ]]
  [[ $output == *"com.on (system, want on): disabled, not loaded"* ]]
  # Read-only.
  ! grep -qE 'launchctl (enable|disable|bootout|bootstrap)' "$STUB_LOG"
}

@test "check: without root and without BI_SFLTOOL, the BTM database is skipped" {
  [ "$(id -u)" != 0 ] || skip "running as root"
  write_config '[]'
  run bi check
  [ "$status" -eq 0 ]
  [[ $output == *"run with sudo"* ]]
}

@test "open at login: adds listed apps, removes only those it added" {
  mkdir -p "$root/Applications/A.app" "$root/Applications/B.app"
  printf '%s\n' "/Applications/Preexisting.app" "$root/Applications/B.app" >"$STUB_STATE/login-items"
  write_config '[]' "[\"$root/Applications/A.app\", \"$root/Applications/B.app/\", \"$root/Applications/Missing.app\"]"
  run bi login-items
  [ "$status" -eq 0 ]
  grep -qxF "$root/Applications/A.app" "$STUB_STATE/login-items"
  [[ $output == *"Missing.app does not exist"* ]]
  # Only A was added by us; B was already there.
  [ "$(cat "$home/Library/Application Support/background-items/open-at-login")" = "$root/Applications/A.app" ]

  # Drop A and B from the list: A (ours) goes, B and Preexisting stay.
  write_config '[]' '[]'
  run bi login-items
  [ "$status" -eq 0 ]
  ! grep -qxF "$root/Applications/A.app" "$STUB_STATE/login-items"
  grep -qxF "$root/Applications/B.app" "$STUB_STATE/login-items"
  grep -qxF "/Applications/Preexisting.app" "$STUB_STATE/login-items"
  [ ! -s "$home/Library/Application Support/background-items/open-at-login" ]
}

@test "open at login: nothing listed and nothing added means no System Events call" {
  write_config '[]'
  : >"$STUB_STATE/gui-session"
  run bi apply
  [ "$status" -eq 0 ]
  [ ! -e "$STUB_STATE/login-items" ]
}

@test "apply runs login-items as the user in the GUI session, or skips without one" {
  mkdir -p "$root/Applications/A.app"
  write_config '[]' "[\"$root/Applications/A.app\"]"
  run bi apply
  [ "$status" -eq 0 ]
  [[ $output == *"no GUI session"* ]]
  [ ! -e "$STUB_STATE/login-items" ]

  : >"$STUB_STATE/gui-session"
  run bi apply
  [ "$status" -eq 0 ]
  grep -q '^launchctl asuser 501 .*/sudo --user=alice -- .* login-items$' "$STUB_LOG"
  grep -qxF "$root/Applications/A.app" "$STUB_STATE/login-items"
}

@test "install-launchers: copies, replaces, and removes only names it installed" {
  dir=$BATS_TEST_TMPDIR/libexec/nix-launchd
  src=$here/../../modules/background-items/launcher.sh
  run "$script" install-launchers --dir "$dir" --source "$src" -- "Nix GC" "Nix Darwin Activation"
  [ "$status" -eq 0 ]
  [ -x "$dir/Nix GC" ] && [ ! -L "$dir/Nix GC" ]
  cmp "$src" "$dir/Nix Darwin Activation"
  touch "$dir/someone-elses-file"

  run "$script" install-launchers --dir "$dir" --source "$src" -- "Nix GC"
  [ "$status" -eq 0 ]
  [ -e "$dir/Nix GC" ]
  [ ! -e "$dir/Nix Darwin Activation" ]
  [ -e "$dir/someone-elses-file" ]

  run "$script" install-launchers --dir "$dir" --source "$src" --
  [ "$status" -eq 0 ]
  [ ! -e "$dir/Nix GC" ]
  [ ! -e "$dir/.managed-by-background-items" ]
  [ -e "$dir/someone-elses-file" ]

  run "$script" install-launchers --dir "$dir" --source "$src" -- "a/b"
  [ "$status" -ne 0 ]
}

@test "launcher waits for the store, then execs the job's command in its own process" {
  src=$here/../../modules/background-items/launcher.sh
  grep -qxF '/bin/wait4path /nix/store' "$src"
  [ "$(tail -n 1 "$src")" = 'exec "$@"' ]
  if [ -x /bin/wait4path ]; then
    run /bin/sh "$src" /bin/sh -c 'echo "$0:$1"' a b
    [ "$output" = "a:b" ]
  fi
}
