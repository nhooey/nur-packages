# nix-darwin module: services.background-items. Keeps the launchd jobs it
# lists on, off or absent, keeps a list of apps open at login, and gives
# nix-darwin's own launchd jobs readable names in System Settings > General >
# Login Items & Extensions. Jobs, files and login items it does not list are
# never touched. Exported by the flake as `darwinModules.background-items`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.background-items;
  inherit (lib) mkOption types;

  user =
    if cfg.user != null then
      cfg.user
    else
      throw "services.background-items.user must name the user whose agents and login items to manage (it defaults to system.primaryUser)";

  # users.users.<user>.home when the configuration declares it (a path, maybe
  # unquoted), else the macOS default.
  declaredHome = config.users.users.${user}.home or null;
  home = if declaredHome == null then "/Users/${user}" else toString declaredHome;
  uid = config.users.users.${user}.uid or null;

  dirsOf = {
    gui = [
      "${home}/Library/LaunchAgents"
      "/Library/LaunchAgents"
    ];
    system = [ "/Library/LaunchDaemons" ];
  };

  expandHome = p: if lib.hasPrefix "~/" p then home + lib.removePrefix "~" p else p;

  # Deleted recursively, so: absolute, below the top level, no `.`, `..` or
  # empty components, no glob characters (paths are never globbed, but one
  # that looks like a glob is almost certainly a mistake).
  safePath =
    p:
    let
      parts = lib.splitString "/" p;
    in
    lib.hasPrefix "/" p
    && builtins.length parts >= 3
    && builtins.all (c: c != "" && c != "." && c != "..") (builtins.tail parts)
    && builtins.match ".*[*?[].*" p == null;

  itemList = lib.mapAttrsToList (label: item: {
    inherit label;
    inherit (item) state domain;
    plists = map (d: "${d}/${label}.plist") dirsOf.${item.domain};
    extraPaths = map expandHome item.extraPaths;
  }) cfg.items;

  absentItems = builtins.filter (i: i.state == "absent") itemList;

  # What background-items.sh reads: from the store when activation and the
  # cleanup job run it, from /etc/background-items/config.json for --check.
  configJSON = builtins.toJSON {
    inherit user uid home;
    dirs = dirsOf;
    items = itemList;
    openAtLogin = cfg.openAtLogin;
    loginItemsState = "${home}/Library/Application Support/background-items/open-at-login";
  };
  configFile = pkgs.writeText "background-items.json" configJSON;

  exe = lib.getExe cfg.package;
  launcher = ./launcher.sh;

  # nix-darwin's launchd jobs, by label, with the environment.* attribute
  # their plist is generated into.
  jobs =
    let
      from =
        files: attrs:
        lib.mapAttrsToList (_: job: {
          inherit files;
          label = job.serviceConfig.Label;
          serviceConfig = job.serviceConfig;
        }) attrs;
    in
    from "launchDaemons" config.launchd.daemons
    ++ from "launchAgents" config.launchd.agents
    ++ from "userLaunchAgents" config.launchd.user.agents;
  jobsByLabel = lib.groupBy (j: j.label) jobs;

  # The job's plist with the launcher put in front of its program and
  # arguments. This is written to environment.<files>."<label>.plist".text
  # rather than to launchd.<…>.serviceConfig.ProgramArguments, as a new value
  # for ProgramArguments built from its current value would be defined in
  # terms of itself; the generated plist is otherwise the one nix-darwin
  # writes (lib.generators.toPlist { escape = true; } of serviceConfig). A
  # `Program` key, which launchd runs in place of argv[0], becomes argv[0].
  launchedPlist =
    name: sc:
    let
      original =
        if sc.ProgramArguments != null then
          (
            if sc.Program != null then
              [ sc.Program ] ++ builtins.tail sc.ProgramArguments
            else
              sc.ProgramArguments
          )
        else
          [ sc.Program ];
    in
    lib.generators.toPlist { escape = true; } (
      sc
      // {
        Program = null;
        ProgramArguments = [ "${cfg.launcherDir}/${name}" ] ++ original;
      }
    );

  launcherOverrides =
    files:
    lib.listToAttrs (
      lib.concatLists (
        lib.mapAttrsToList (
          label: name:
          map (
            j: lib.nameValuePair "${label}.plist" { text = lib.mkForce (launchedPlist name j.serviceConfig); }
          ) (builtins.filter (j: j.files == files) (jobsByLabel.${label} or [ ]))
        ) cfg.launcherNames
      )
    );

  launcherNameList = builtins.attrValues cfg.launcherNames;
  validLauncherName =
    n: n != "" && !(lib.hasPrefix "." n) && !(lib.hasInfix "/" n) && !(lib.hasInfix "\n" n);
in
{
  options.services.background-items = {
    enable = lib.mkEnableOption ''
      background-items: on every activation, the launchd jobs listed in
      `items` are brought to their state, the `openAtLogin` apps kept open at
      login, and the jobs in `launcherNames` run through launchers named for
      System Settings. It installs `background-items`, whose
      `background-items --check` reports drift
    '';

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The `background-items` command the module runs and installs.";
    };

    user = mkOption {
      type = types.nullOr types.str;
      default = config.system.primaryUser or null;
      defaultText = lib.literalExpression "config.system.primaryUser";
      example = "alice";
      description = ''
        The user whose launchd agents (domain `gui/<uid>`), `~/Library/LaunchAgents`
        and login items the module manages.
      '';
    };

    items = mkOption {
      default = { };
      example = lib.literalExpression ''
        {
          "com.google.keystone.agent" = {
            domain = "gui";
            state = "absent";
            extraPaths = [ "~/Library/Application Support/Google/GoogleUpdater" ];
          };
          "com.google.keystone.daemon" = { domain = "system"; state = "absent"; };
          "com.example.helper" = { domain = "gui"; state = "off"; };
        }
      '';
      description = ''
        launchd jobs, by label, and the state each is kept in on every
        activation. A job that is not listed is not tracked or changed in
        any way: there is no implicit "off". `background-items --check`
        reports listed jobs whose state has drifted, and lists the jobs found
        that are not listed here.

        Known limits:
        - An "off" job may still show its switch (turned on or off) in System
          Settings > General > Login Items & Extensions: that list comes from
          the Background Task Management database (`sfltool dumpbtm`), which
          `launchctl disable` does not update.
        - Helpers that apps register with SMAppService (for example
          1Password Launcher, iStat Menus, MiniCalendar, Paragon FSMenu) may
          not honour `launchctl disable`, and the app may register them
          again; turn those off in the app or in System Settings.
        - A `gui` agent in /Library/LaunchAgents loads for every user who
          logs in; only `user`'s `gui/<uid>` domain is changed.
      '';
      type = types.attrsOf (
        types.submodule {
          options = {
            state = mkOption {
              type = types.enum [
                "on"
                "off"
                "absent"
              ];
              description = ''
                - `"on"`: `launchctl enable`, then `launchctl bootstrap` from
                  its plist if one exists and the job is not loaded.
                - `"off"`: `launchctl disable`, then `launchctl bootout`.
                - `"absent"`: `launchctl bootout`, then delete
                  `<label>.plist` from the domain's folders
                  (`~/Library/LaunchAgents` and `/Library/LaunchAgents` for
                  `gui`, `/Library/LaunchDaemons` for `system`) and every
                  `extraPaths` entry. Deleted by exact name, never by
                  pattern. A launchd daemon watching those folders runs the
                  removal again whenever they change, so an app that
                  reinstalls the plist (for example in an update) loses it
                  again.
              '';
            };
            domain = mkOption {
              type = types.enum [
                "gui"
                "system"
              ];
              description = ''
                Where the job runs: `"system"` for a daemon
                (`/Library/LaunchDaemons`, domain `system`), `"gui"` for an
                agent of `user` (`~/Library/LaunchAgents` or
                `/Library/LaunchAgents`, domain `gui/<uid>`).
              '';
            };
            extraPaths = mkOption {
              type = types.listOf types.str;
              default = [ ];
              example = [ "~/Library/Application Support/Google/GoogleUpdater" ];
              description = ''
                Further files or folders deleted (recursively) when `state`
                is `"absent"`. Each is an absolute path, or one starting with
                `~/` for `user`'s home, at least two levels deep.
              '';
            };
          };
        }
      );
    };

    openAtLogin = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "/Applications/Rectangle.app" ];
      description = ''
        Apps kept in `user`'s Open at Login list, through System Events
        (osascript) in the user's GUI session. Only these are added; an app
        removed from this list is removed from Open at Login only if the
        module added it (recorded in
        `~/Library/Application Support/background-items/open-at-login`).
        Login items the module did not add are never removed. The first run
        asks once for Automation permission to control System Events; while
        the user is not logged in, the update waits for the next activation.
      '';
    };

    launcherNames = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        "org.nixos.nix-gc" = "Nix GC";
        "org.nixos.activate-system" = "Nix Darwin Activation";
      };
      description = ''
        Names for nix-darwin's launchd jobs, by label, in System Settings >
        General > Login Items & Extensions. It names an unsigned job after
        the program its plist runs, so nix-darwin's jobs, which run
        `/bin/sh`, all show as "sh". For each job listed, a launcher with the
        given name is copied (not linked: daemons start before /nix is
        mounted) to `launcherDir`, and the job's plist runs it in front of
        its own program and arguments; the launcher waits for /nix/store,
        then `exec`s them, so the PID and signals stay the job's. Jobs not
        listed are not changed.

        Each label must be a job nix-darwin defines (`launchd.daemons`,
        `launchd.agents` or `launchd.user.agents`), which includes
        org.nixos.nix-daemon. org.nixos.darwin-store (shown as "diskutil")
        is not one: the Nix installer writes it, it mounts /nix itself, and
        breaking it leaves /nix unmounted at boot, so it is not supported.
        If a launcher for org.nixos.nix-daemon goes missing, the daemon does
        not start until the next `sudo darwin-rebuild switch` (which runs as
        root without the daemon) reinstalls it.
      '';
    };

    launcherDir = mkOption {
      type = types.str;
      default = "/usr/local/libexec/nix-launchd";
      description = ''
        Where the `launcherNames` launchers are installed, outside /nix. The
        module owns this folder's launchers: one it installed whose job is
        no longer listed is deleted, by name.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      lib.mapAttrsToList (label: _: {
        assertion = jobsByLabel ? ${label};
        message =
          "services.background-items.launcherNames.\"${label}\": no nix-darwin launchd job has this label"
          + lib.optionalString (label == "org.nixos.darwin-store") (
            " (org.nixos.darwin-store is written by the Nix installer, not nix-darwin, and is not supported:"
            + " it mounts /nix itself)"
          )
          + ".";
      }) cfg.launcherNames
      ++ map (name: {
        assertion = validLauncherName name;
        message = "services.background-items.launcherNames: \"${name}\" is not a valid file name (empty, starts with a dot, or contains / or a newline).";
      }) launcherNameList
      ++ [
        {
          assertion = builtins.length (lib.unique launcherNameList) == builtins.length launcherNameList;
          message = "services.background-items.launcherNames: two jobs have the same name.";
        }
      ]
      ++ lib.concatMap (
        i:
        map (p: {
          assertion = safePath p;
          message = "services.background-items.items.\"${i.label}\".extraPaths: \"${p}\" must be absolute (or start with ~/), at least two levels deep, and free of ., .., empty components and glob characters.";
        }) i.extraPaths
      ) itemList;

    environment.systemPackages = [ cfg.package ];
    environment.etc."background-items/config.json".text = configJSON;

    # Before nix-darwin's `launchd` step loads the plists that run them.
    system.activationScripts.extraActivation.text = lib.mkAfter ''
      echo "setting up background-items launchers..." >&2
      ${exe} install-launchers --dir ${lib.escapeShellArg cfg.launcherDir} --source ${launcher} -- ${lib.escapeShellArgs launcherNameList} ||
        echo "background-items: installing launchers failed" >&2
    '';

    # After Homebrew, whose casks may (re)install the plists of listed jobs.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "applying background-items..." >&2
      ${exe} --config ${configFile} apply || echo "background-items: apply failed" >&2
    '';

    launchd.daemons.background-items-cleanup = lib.mkIf (absentItems != [ ]) {
      command = "${exe} --config ${configFile} cleanup";
      serviceConfig = {
        WatchPaths = lib.unique (map dirOf (lib.concatMap (i: i.plists) absentItems));
        RunAtLoad = false;
        ThrottleInterval = 30;
        StandardOutPath = "/var/log/background-items.log";
        StandardErrorPath = "/var/log/background-items.log";
      };
    };

    environment.launchDaemons = launcherOverrides "launchDaemons";
    environment.launchAgents = launcherOverrides "launchAgents";
    environment.userLaunchAgents = launcherOverrides "userLaunchAgents";
  };
}
